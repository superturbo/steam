module Locomotive
  module Steam
    module Adapters
      module Filesystem
        module YAMLLoaders

          class ContentEntry

            include Adapters::Filesystem::YAMLLoader

            def load(scope)
              super
              load_list
            end

            private

            def load_list
              [].tap do |list|
                each(content_type_slug) do |label, attributes, position|
                  _attributes = { _position: position, _label: label.to_s }.merge(attributes || {})

                  # A missing _visible key means visible in Wagon files.
                  _attributes[:_visible] = true unless _attributes.key?(:_visible)

                  modify_for_selects(_attributes, label)
                  modify_for_associations(_attributes)
                  modify_for_files(_attributes)
                  modify_for_passwords(_attributes)
                  modify_for_values(_attributes, label)

                  list << _attributes
                end

                reject_repeated_slugs(list)
                validate_position_groups!(list)
              end
            end

            # A group either states every position or falls back to _position.
            def validate_position_groups!(list)
              belongs_to_names = content_type.association_fields
                                             .select { |field| field.type == :belongs_to }
                                             .map { |field| field.name.to_s }

              validate_position_names!(list, belongs_to_names)
              belongs_to_names.each { |name| validate_position_groups_for!(list, name) }
            end

            def validate_position_names!(list, belongs_to_names)
              list.each do |attributes|
                attributes.each_key do |key|
                  next unless (name = key.to_s[/\Aposition_in_(.+)\z/, 1])
                  next if belongs_to_names.include?(name)

                  entries_file_error!(:unknown_association, attributes,
                                      "position_in_#{name} names no belongs_to field")
                end
              end
            end

            def validate_position_groups_for!(list, name)
              position_key = :"position_in_#{name}"

              list.each do |attributes|
                next unless attributes.key?(position_key)

                position = attributes[position_key]

                if attributes[:"#{name}_id"].blank?
                  entries_file_error!(:unlinked_position, attributes,
                                      "position_in_#{name} without a linked #{name}")
                end

                unless position.is_a?(Integer) && position >= 0 && Adapters::NumericBounds.within?(position)
                  entries_file_error!(:invalid_position, attributes,
                                      "position_in_#{name} takes a non-negative 64-bit integer")
                end
              end

              list.group_by { |attributes| attributes[:"#{name}_id"] }.each do |parent, entries|
                next if parent.blank?

                positioned_entries = entries.select { |attributes| attributes.key?(position_key) }

                next if positioned_entries.empty?

                if positioned_entries.size < entries.size
                  group_error!(:partial_position_group, name, parent,
                               "position_in_#{name} must be set for every entry in the group")
                end

                if positioned_entries.map { |attributes| attributes[position_key] }.uniq.size < positioned_entries.size
                  group_error!(:duplicate_position, name, parent, "duplicate position_in_#{name}")
                end
              end
            end

            def entries_file_error!(reason, attributes, message)
              raise Locomotive::Steam::InvalidEntriesFileError.new(
                reason,
                "#{File.join(path, "#{content_type_slug}.yml")}, entry #{attributes[:_label]}: #{message}")
            end

            def group_error!(reason, name, parent, message)
              raise Locomotive::Steam::InvalidEntriesFileError.new(
                reason,
                "#{File.join(path, "#{content_type_slug}.yml")}, entries of #{name} #{parent}: #{message}")
            end

            def reject_repeated_slugs(list)
              claimed = Hash.new { |slugs, slug| slugs[slug] = [] }

              list.each do |attributes|
                spelled_slugs(attributes[:_slug]).each do |locale, slug|
                  claimed[slug].each do |claimed_locale, label|
                    next unless locale.nil? || claimed_locale.nil? || locale == claimed_locale

                    repeated_slug!(label, attributes[:_label], slug, locale || claimed_locale)
                  end

                  claimed[slug] << [locale, attributes[:_label]]
                end
              end
            end

            def spelled_slugs(slug)
              return {} if slug.blank?

              # A scalar slug applies to every locale.
              slug.is_a?(Hash) ? slug : { nil => slug }
            end

            def repeated_slug!(first, second, slug, locale)
              raise "#{File.join(path, "#{content_type_slug}.yml")}, entries #{first} and #{second}: " \
                    "#{"locale #{locale}, " if locale}duplicate slug #{slug.inspect}"
            end

            # Invalid values fail while their source entry and field are still known.
            def modify_for_values(attributes, label)
              content_type.fields_by_name.each_value do |field|
                name = field.persisted_name&.to_sym
                next unless name && attributes.key?(name)

                begin
                  attributes[name] = normalized_value(field, attributes[name])
                rescue Locomotive::Steam::ContentFieldValues::ParseError => e
                  raise e.class.new(e.reason,
                                    "#{File.join(path, "#{content_type_slug}.yml")}, entry #{label}, " \
                                    "field #{field.name}: #{e.message}")
                end
              end
            end

            def normalized_value(field, value)
              return normalize_value(field, value) unless field.localized? && value.is_a?(Hash)

              value.to_h do |locale, translated|
                begin
                  [locale, normalize_value(field, translated)]
                rescue Locomotive::Steam::ContentFieldValues::ParseError => e
                  raise e.class.new(e.reason, "locale #{locale}, #{e.message}")
                end
              end
            end

            def normalize_value(field, value)
              Locomotive::Steam::ContentFieldValues.normalize_input(field.type, value, @scope.site)
            end

            def modify_for_selects(attributes, label)
              content_type.select_fields.each do |field|
                next unless attributes.key?(field.name.to_sym)

                if (option = attributes.delete(field.name.to_sym)).is_a?(Hash)
                  unless field.localized?
                    raise Locomotive::Steam::ContentFieldValues::ParseError.new(
                      :wrong_type,
                      "#{File.join(path, "#{content_type_slug}.yml")}, entry #{label}, " \
                      "field #{field.name}: a locale hash for a select that is not localized")
                  end

                  attributes[field.persisted_name.to_sym] = option.inject({}) do |memo, (locale, name)|
                    field.select_options.scope.with_locale(locale) do
                      memo[locale] = option_id!(field, name, label, locale)
                    end
                    memo
                  end
                else
                  # A YAML scalar names the option in the default locale and
                  # reads as the every-locale fallback.
                  attributes[field.persisted_name.to_sym] = field.select_options.scope.with_locale(default_locale) do
                    option_id!(field, option, label)
                  end
                end
              end
            end

            def option_id!(field, name, label, locale = nil)
              return nil if name.nil?

              option = field.select_options.by_name(name)

              option&._id || raise(Locomotive::Steam::ContentFieldValues::ParseError.new(
                :unknown_select_option,
                "#{File.join(path, "#{content_type_slug}.yml")}, entry #{label}, " \
                "field #{field.name}#{", locale #{locale}" if locale}: unknown select option"))
            end

            def modify_for_files(attributes)
              content_type.file_fields.each do |field|
                next unless attributes.key?(field.name.to_sym)

                attributes[:"#{field.name}_size"] ||= {}
                value = attributes[:"#{field.name}_size"]

                if (path = attributes[field.name.to_sym]).is_a?(Hash)
                  path.each { |locale, path| value[locale.to_s] = file_size(path) }
                else
                  value['default'] = file_size(path)
                end
              end
            end

            def modify_for_passwords(attributes)
              content_type.password_fields.each do |field|
                next unless attributes.key?(field.name.to_sym)

                password = attributes.delete(field.name.to_sym)
                attributes[:"#{field.name}_hash"] =
                  password.nil? ? nil : BCrypt::Password.create(password)
              end
            end

            def file_size(path)
              return nil if path.blank?

              _path = File.join(site_path, 'public', path)

              File.exist?(_path) ? File.size(_path) : nil
            end

            def modify_for_associations(attributes)
              content_type.association_fields.each do |field|
                case field.type
                when :belongs_to
                  modify_belongs_to_association(field, attributes)
                when :many_to_many
                  modify_many_to_many_association(field, attributes)
                end
              end
            end

            def modify_belongs_to_association(field, attributes)
              return unless attributes.key?(field.name.to_sym)

              id = attributes.delete(field.name.to_sym)
              attributes[:"#{field.name}_id"] = id
            end

            def modify_many_to_many_association(field, attributes)
              return unless attributes.key?(field.name.to_sym)

              attributes[:"#{field.name.to_s.singularize}_ids"] = attributes.delete(field.name.to_sym)
            end

            def each(slug, &block)
              position = 0
              _load(File.join(path, "#{slug}.yml")).each do |element|
                label, attributes = if element.respond_to?(:keys)
                  [element.keys.first, element.values.first]
                else
                  [element, {}]
                end
                yield(label, attributes, position)
                position += 1
              end
            end

            def path
              return @path if @path # memoization

              path = File.join(site_path, 'data', env.to_s, 'content_entries')

              @path = File.exist?(path) ? path : File.join(site_path, 'data') # allow the legacy folder
            end

            def content_type
              @scope.context[:content_type]
            end

            def content_type_slug
              content_type.slug
            end

          end

        end
      end
    end
  end
end
