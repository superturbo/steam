require 'sanitize'

module Locomotive
  module Steam

    class ContentEntryService

      include Locomotive::Steam::Services::Concerns::Decorator

      PUBLIC_BUILT_IN_NAMES = %w(_slug seo_title meta_description meta_keywords).freeze
      WRITTEN_BY_NAME       = %i(string text email color integer float date date_time
                                 boolean json tags).freeze
      REFUSED_INPUT_NAME    = '_input'

      private_constant :PUBLIC_BUILT_IN_NAMES, :WRITTEN_BY_NAME, :REFUSED_INPUT_NAME

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
          entry = _repository.by_slug(id_or_slug) || _repository.find(id_or_slug)
          _decorate(entry, as_json)
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

          logEntryOperation(type_slug, decorated_entry)

          _json_decorate(decorated_entry, as_json)
        end
      end

      def update(type_slug, id_or_slug, attributes, as_json = false)
        with_repository(type_slug) do |_repository|
          entry             = _repository.by_slug(id_or_slug) || _repository.find(id_or_slug)
          accepted, refused = split_public_input(_repository.content_type, attributes)
          _attributes       = prepare_attributes(_repository, accepted)

          decorated_entry = i18n_decorate { entry.change(_attributes, locale) }
          entry.refuse_input(refused)

          _repository.update(entry) if validate(_repository, decorated_entry)

          logEntryOperation(type_slug, decorated_entry)

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

          logEntryOperation(decorated_entry.content_type.slug, decorated_entry)

          decorated_entry
        end
      end

      def delete(type_slug, id_or_slug)
        with_repository(type_slug) do |_repository|
          entry = _repository.by_slug(id_or_slug) || _repository.find(id_or_slug)
          _repository.delete(entry)
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

      def logEntryOperation(type_slug, entry)
        if (json = entry.as_json)['errors'].blank?
          logger.info "[#{type_slug}] Entry persisted with success. #{json}"
        else
          logger.error "[#{type_slug}] Failed to persist entry. #{json}"
        end
      end

      def with_repository(type_or_slug)
        type = type_or_slug.respond_to?(:fields) ? type_or_slug : get_type(type_or_slug)

        return if type.nil?

        yield(repository.with(type))
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

        fields       = _repository.content_type.fields
        links        = fields.associations.select { |field| field.type == :belongs_to }
        skipped_keys = fields.json.map { |field| field.name.to_s } +
                       fields.selects.map { |field| field.persisted_name.to_s } +
                       links.map(&:persisted_name)

        # JSON is validated as data; HTML escaping belongs to rendering.
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
        # simple validations (existence of values) first
        entry.valid?

        # check if the entry has unique values for its
        # fields marked as unique
        content_type_repository.look_for_unique_fields(entry.content_type).each do |name, _|
          next if entry.errors[name].present?

          if _repository.exists?(name => entry.send(name), :"_id.ne" => entry._id)
            entry.errors.add(name, :taken)
          end
        end

        entry.errors.empty?
      end

    end

  end
end

