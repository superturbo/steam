require 'sanitize'

module Locomotive
  module Steam

    class ContentEntryService

      include Locomotive::Steam::Services::Concerns::Decorator

      SEO_NAMES             = %w(seo_title meta_description meta_keywords).freeze
      PUBLIC_BUILT_IN_NAMES = (%w(_slug) + SEO_NAMES).freeze
      WRITTEN_BY_NAME       = %i(string text email color integer float date date_time
                                 boolean json tags).freeze
      REFUSED_INPUT_NAME    = '_input'

      private_constant :SEO_NAMES, :PUBLIC_BUILT_IN_NAMES, :WRITTEN_BY_NAME, :REFUSED_INPUT_NAME

      attr_accessor_initialize :content_type_repository, :repository, :locale

      def all(type_slug, conditions = {}, as_json = false)
        with_repository(type_slug) do |_repository|
          _repository.all(conditions).map do |entry|
            _decorate(entry, as_json)
          end
        end
      end

      def find(type_slug, id_or_slug, as_json = false)
        with_repository(type_slug) do |_repository|
          _decorate(find_entry(_repository, id_or_slug), as_json)
        end
      end

      def build(type_slug, attributes)
        with_repository(type_slug) do |_repository|
          accepted, refused = split_public_input(_repository.content_type, attributes)
          _attributes = prepare_attributes(_repository, accepted)

          entry = _repository.build(_attributes)
          entry.refuse_input(refused)

          i18n_decorate { entry }
        end
      end

      def create(type_slug, attributes, as_json = false)
        with_repository(type_slug) do |_repository|
          accepted, refused = split_public_input(_repository.content_type, attributes)
          _attributes = prepare_attributes(_repository, accepted)

          entry = _repository.build(_attributes)
          entry.refuse_input(refused)

          yield(entry) if block_given?

          decorated_entry = i18n_decorate { entry }

          if validate(_repository, decorated_entry)
            _repository.create(entry)
          end

          log_entry_write(decorated_entry)

          _json_decorate(decorated_entry, as_json)
        end
      end

      def update(type_slug, id_or_slug, attributes, as_json = false)
        with_repository(type_slug) do |_repository|
          entry             = find_write_target!(_repository, id_or_slug)
          accepted, refused = split_public_input(_repository.content_type, attributes)
          _attributes       = prepare_attributes(_repository, accepted)

          decorated_entry = i18n_decorate { entry.change(_attributes, locale) }
          entry.refuse_input(refused)

          _repository.update(entry) if validate(_repository, decorated_entry)

          log_entry_write(decorated_entry)

          _json_decorate(decorated_entry, as_json)
        end
      end

      # Warning: does not work with file fields
      def update_decorated_entry(decorated_entry, attributes)
        with_repository(decorated_entry.content_type) do |_repository|
          entry       = decorated_entry.__getobj__
          _attributes = prepare_attributes(_repository, attributes)

          # A refused write must not reach the entry the caller is holding.
          candidate = entry.dup
          candidate.change(_attributes, locale)

          _repository.update(candidate)

          # Keep the caller's decorator attached to the written entity.
          decorated_entry.__setobj__(candidate)

          log_entry_write(decorated_entry)

          decorated_entry
        end
      end

      def delete(type_slug, id_or_slug)
        with_repository(type_slug) do |_repository|
          _repository.delete(find_write_target!(_repository, id_or_slug))
        end
      end

      def get_type(slug)
        return nil if slug.blank?

        content_type_repository.by_slug(slug)
      end

      def logger
        Locomotive::Common::Logger
      end

      private

      # Filesystem IDs, labels and undeclared names can hold visitor text.
      def log_entry_write(entry)
        type = "[#{entry.content_type.slug}]"
        id   = " (#{entry._id})" if repository.adapter.native_id?(entry._id)

        if entry.errors.empty?
          logger.info "#{type} Entry persisted with success#{id}"
        else
          logger.error "#{type} Failed to persist entry#{id}: #{logged_error_codes(entry.content_type, entry.errors.codes)}"
        end

        logger.debug "#{type} Entry attributes: #{debug_entry_details(entry)}" if logger.instance.logger&.debug?
      end

      def logged_error_codes(content_type, codes)
        declared = content_type.fields_by_name.keys.map(&:to_s) + public_input_names(content_type)

        codes.flat_map do |name, list|
          logged_name = declared.include?(name.to_s) ? name : REFUSED_INPUT_NAME
          list.map { |code| "#{logged_name}=#{code}" }
        end.uniq.join(', ')
      end

      # Filtered by name, with the error messages as written.
      def debug_entry_details(entry)
        attributes = entry.as_json

        LogFilter.params(attributes.except('errors')).merge(attributes.slice('errors')).inspect
      end

      def with_repository(type_or_slug)
        type = type_or_slug.respond_to?(:fields) ? type_or_slug : get_type(type_or_slug)

        return if type.nil?

        yield(repository.with(type))
      end

      # Write targets include hidden entries.
      def find_write_target!(_repository, id_or_slug)
        find_entry(_repository, id_or_slug, _visible: nil) ||
          raise(Models::Repository::RecordNotFound, 'could not find the content entry')
      end

      # A blank identifier names no entry.
      def find_entry(_repository, id_or_slug, **visibility)
        return if id_or_slug.blank?

        _repository.first(_slug: id_or_slug, **visibility) || _repository.first(_id: id_or_slug, **visibility)
      end

      def _decorate(entry, as_json)
        decorated_entry = i18n_decorate { entry }
        _json_decorate(decorated_entry, as_json)
      end

      def _json_decorate(entry, as_json)
        as_json ? entry.as_json : entry
      end

      def split_public_input(content_type, attributes)
        attributes = {} if attributes.nil?
        return [{}, [REFUSED_INPUT_NAME]] unless attributes.is_a?(Hash)

        names = public_input_names(content_type)

        accepted = attributes.select { |key, _| names.include?(key.to_s) }
        refused  = attributes.keys.reject { |key| names.include?(key.to_s) }

        [accepted, refused.map { |key| refused_input_name(key) }.uniq]
      end

      # Stored schemas can bypass loader validation; conflicted names grant no input.
      def public_input_names(content_type)
        names = content_type.fields_by_name.each_value.flat_map do |field|
          case field.type
          when *WRITTEN_BY_NAME           then [field.name.to_s]
          when :select                    then [field.name.to_s, field.persisted_name.to_s]
          when :belongs_to                then [field.name.to_s, field.persisted_name.to_s]
          when :many_to_many              then [field.persisted_name.to_s]
          when :password                  then [field.name.to_s, "#{field.name}_confirmation"]
          else []
          end
        end

        names + PUBLIC_BUILT_IN_NAMES - content_type.invalid_entry_names
      end

      # A key shaped like no attribute name is not echoed back.
      def refused_input_name(key)
        name = key.to_s

        name.valid_encoding? && name.match?(/\A[a-z_]\w{0,63}\z/i) ? name : REFUSED_INPUT_NAME
      end

      def prepare_attributes(_repository, attributes)
        # Option names and link references are data to look up, not text to render.
        attributes = _repository.resolve_belongs_to(_repository.resolve_selects(attributes))
        attributes = _repository.resolve_many_to_many(attributes)

        fields       = _repository.content_type.fields
        links        = fields.associations.select { |field| field.type == :belongs_to }
        declared     = _repository.content_type.fields_by_name.each_value
        passwords    = declared.select(&:write_only?)
        # An email address is data, not HTML: cleaning would turn a&b into a&amp;b.
        skipped_keys = SEO_NAMES +
                       declared.select { |field| field.type == :email }.map { |field| field.name.to_s } +
                       fields.json.map { |field| field.name.to_s } +
                       fields.selects.map { |field| field.persisted_name.to_s } +
                       links.map(&:persisted_name) +
                       passwords.flat_map { |field| [field.name.to_s, "#{field.name}_confirmation"] }

        attributes.each do |key, value|
          next unless value.is_a?(String)
          next if skipped_keys.include?(key.to_s)

          text = sanitizable_text(value)
          next unless text

          attributes[key] = Sanitize.clean(text, Sanitize::Config::BASIC)
        end

        attributes
      end

      def sanitizable_text(value)
        ContentFieldValues.normalize_input(:string, value)
      rescue ContentFieldValues::ParseError
        nil
      end

      def validate(_repository, entry)
        entry.valid?

        content_type_repository.look_for_unique_fields(entry.content_type).each do |name, field|
          next if entry.errors[name].present?

          entry.errors.add(name, :taken) if taken?(_repository, entry, field)
        end

        entry.errors.empty?
      end

      # Check each site locale, including scalar fallbacks.
      def taken?(_repository, entry, field)
        key    = field.persisted_name
        stored = entry[key.to_sym]
        values = if stored.respond_to?(:translations)
                   _repository.site.locales.to_h { |site_locale| [site_locale, stored[site_locale]] }
                 else
                   { locale => stored }
                 end

        values.any? do |value_locale, value|
          next false if value.nil? || value == ''

          # A hidden entry holds its value too.
          _repository.in_locale(value_locale).exists?(key => value, :"_id.ne" => entry._id, _visible: nil)
        end
      end

    end

  end
end

