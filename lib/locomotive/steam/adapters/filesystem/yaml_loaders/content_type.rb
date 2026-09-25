module Locomotive
  module Steam
    module Adapters
      module Filesystem
        module YAMLLoaders

          class ContentType

            include Adapters::Filesystem::YAMLLoader

            def load(scope)
              super
              load_list
            end

            private

            def load_list
              [].tap do |array|
                each_file do |filepath, slug|
                  attributes = _load(filepath)
                  attributes[:entries_custom_fields] = build_fields(attributes.delete(:fields), filepath)
                  reject_write_only_label!(attributes, filepath)
                  array << { _id: slug.to_s, slug: slug }.merge(attributes)
                end
              end
            end

            def build_fields(list, filepath)
              list.each_with_index.map do |attributes, index|
                build_field(attributes.keys.first, attributes.values.first, index, filepath)
              end.tap { |fields| validate_namespace!(fields, filepath) }
            end

            def build_field(name, attributes, position, filepath)
              attributes.tap do |attributes|
                attributes[:_id]      = name.to_s
                attributes[:name]     = name.to_s
                attributes[:type]     = (attributes[:type] || 'string').to_s.downcase
                attributes[:position] ||= position

                if attributes[:label].blank?
                  attributes[:label] = name.to_s.humanize
                end

                validate_name!(attributes, filepath)
                validate_capabilities!(attributes, filepath)

                if select_options = attributes.delete(:select_options)
                  attributes[:select_options] = build_select_options(select_options)
                end
              end
            end

            def validate_name!(attributes, filepath)
              name = attributes[:name]

              return unless Locomotive::Steam::ContentTypeField.reserved_name?(name)

              raise Locomotive::Steam::UnsupportedSchemaError.new(:reserved_field_name,
                "#{filepath}, field #{name}: #{name} is a reserved name")
            end

            def validate_namespace!(fields, filepath)
              duplicate, _ = fields.map { |attributes| attributes[:name] }
                                   .tally.find { |_, count| count > 1 }

              if duplicate
                raise Locomotive::Steam::UnsupportedSchemaError.new(:colliding_field_name,
                  "#{filepath}, field #{duplicate}: declared more than once")
              end

              entities = fields.map do |attributes|
                Locomotive::Steam::ContentTypeField.new(name: attributes[:name], type: attributes[:type])
              end

              Locomotive::Steam::ContentType.entry_name_owners(entities).each do |name, owners|
                next unless owners.size > 1

                names = owners.map { |owner| owner.name.to_s }.sort.to_sentence

                raise Locomotive::Steam::UnsupportedSchemaError.new(:colliding_field_name,
                  "#{filepath}: fields #{names} share the entry name #{name}")
              end
            end

            def validate_capabilities!(attributes, filepath)
              field = Locomotive::Steam::ContentTypeField.new(type: attributes[:type])

              unless field.supported?
                raise Locomotive::Steam::UnsupportedSchemaError.new(:unknown_field_type,
                  "#{filepath}, field #{attributes[:name]}: unknown field type #{attributes[:type].inspect}")
              end

              if attributes[:localized] && !field.supports_localization?
                raise Locomotive::Steam::UnsupportedSchemaError.new(:unsupported_localization,
                  "#{filepath}, field #{attributes[:name]}: a #{attributes[:type]} field cannot be localized")
              end

              if attributes[:required] && !field.supports_required?
                raise Locomotive::Steam::UnsupportedSchemaError.new(:unsupported_required,
                  "#{filepath}, field #{attributes[:name]}: a #{attributes[:type]} field cannot be required")
              end

              if attributes[:unique] && field.write_only?
                raise Locomotive::Steam::UnsupportedSchemaError.new(:unsupported_unique,
                  "#{filepath}, field #{attributes[:name]}: a #{attributes[:type]} field cannot be unique")
              end
            end

            def reject_write_only_label!(attributes, filepath)
              fields = attributes[:entries_custom_fields]
              name   = (attributes[:label_field_name] || fields.first&.fetch(:name)).to_s
              label  = fields.find { |field| field[:name] == name }
              return unless label

              field = Locomotive::Steam::ContentTypeField.new(type: label[:type])
              return unless field.write_only?

              raise Locomotive::Steam::UnsupportedSchemaError.new(:unsupported_label,
                "#{filepath}, field #{name}: a #{label[:type]} field cannot be the label")
            end

            def build_select_options(options)
              if options.is_a?(Hash)
                build_select_options_from_hash(options)
              else
                build_select_options_from_array(options)
              end
            end

            def build_select_options_from_hash(options)
              [].tap do |list|
                options.each do |locale, values|
                  values.each_with_index do |name, position|
                    if (option = list.at(position)).nil?
                      list << { _id: position.to_s, name: { locale => name }, position: position }
                    else
                      option[:name][locale] = name
                    end
                  end
                end
              end
            end

            def build_select_options_from_array(options)
              [].tap do |list|
                options.each_with_index do |name, position|
                  # _id = name.is_a?(Hash) ? name.values.first : name
                  list << { _id: position, name: name, position: position }
                end
              end
            end

            def each_file(&block)
              Dir.glob(File.join(path, "*.yml")).each do |filepath|
                slug = File.basename(filepath, '.yml')
                yield(filepath, slug)
              end
            end

            def path
              File.join(site_path, 'app', 'content_types')
            end

          end

        end
      end
    end
  end
end
