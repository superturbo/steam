require_relative 'json_file'

module Locomotive::Steam
  module Adapters
    module Filesystem

      module YAMLLoader

        extend Forwardable

        def_delegators :@scope, :locales, :default_locale

        attr_reader :site_path, :env

        def initialize(site_path, env = :local)
          @site_path, @env = site_path, env
        end

        def load(scope = nil)
          @scope = scope
        end

        def _load(path, frontmatter = false, strict = false, &block)
          if File.exist?(path)
            yaml      = File.open(path).read.force_encoding('utf-8')
            template  = nil

            unless yaml.valid_encoding?
              raise Locomotive::Steam::TemplateError.new('The file is not valid UTF-8', path, nil, nil, nil)
            end

            # JSON header?
            if frontmatter && match = yaml.match(JSON_FRONTMATTER_REGEXP)
              json, template = match[:json], match[:template]
              safe_json_load(json, template, path, &block)

            # YAML header?
            elsif frontmatter && match = yaml.match(strict ? YAML_FRONTMATTER_REGEXP : FRONTMATTER_REGEXP)
              yaml, template = match[:yaml], match[:template]
              safe_yaml_load(yaml, template, path) do |attributes, header_template|
                check_header(attributes, path)
                block&.call(attributes, header_template)
              end

            elsif frontmatter
              message = 'Your file requires a valid YAML or JSON header'
              raise Locomotive::Steam::TemplateError.new(message, path, yaml, 0, nil)

            # YAML by default
            else
              safe_yaml_load(yaml, template, path, &block)
            end
          else
            Locomotive::Common::Logger.error "No #{path} file found"
            {}
          end
        end

        def safe_yaml_load(yaml, template, path, &block)
          return {} if yaml.blank?

          HashConverter.to_sym(parse_yaml(yaml, path)).tap do |attributes|
            block.call(attributes, template) if block_given?
          end
        end

        # Keep the file path on YAML parsing and key errors.
        def parse_yaml(yaml, path)
          document = begin
            YAML.load(yaml)
          rescue Psych::Exception => e
            raise "Malformed YAML in this file #{path}, error: #{e.message}"
          end

          return document if text_keys?(document)

          raise "Malformed YAML in this file #{path}, error: every key must be text"
        end

        def text_keys?(value)
          case value
          when Hash  then value.all? { |key, nested| (key.is_a?(String) || key.is_a?(Symbol)) && text_keys?(nested) }
          when Array then value.all? { |nested| text_keys?(nested) }
          else true
          end
        end

        # A header holds the attributes of its template.
        def check_header(attributes, path)
          return if attributes.is_a?(Hash)

          raise Locomotive::Steam::TemplateError.new('The header must hold attributes', path, nil, nil, nil)
        end

        def safe_json_load(json, template, path, &block)
          return {} if JsonFile.blank?(json, path)

          JsonFile.parse(json, path).tap do |attributes|
            block.call(attributes, template) if block_given?
          end
        end

        def safe_json_file_load(path)
          return {} unless File.exist?(path)

          json = File.read(path)

          safe_json_load(json, nil, path)
        end

        def template_extensions
          @extensions ||= %w(liquid haml)
        end

      end

    end
  end
end
