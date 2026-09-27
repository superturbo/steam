module Locomotive
  module Steam
    module Liquid
      module Filters
        module Json

          # When serialization gives valid JSON, the output is safe as a value
          # inside an HTML script element, whatever the host's JSON escaping settings.
          def json(input, fields = [])
            if fields && fields.is_a?(String)
              fields = fields.split(',').map(&:strip)
            end

            ERB::Util.json_escape(serialize_json(input, fields))
          end

          # without the leading and trailing braces/brackets
          # useful to add a prperty to an object or an element to an array
          def open_json(input)
            if input =~ /\A[\{\[](.*)[\}\]]\Z/m
              $1
            else
              input
            end
          end

          protected

          def serialize_json(input, fields)
            if input.is_a?(Hash)
              object_to_json(input, fields)
            elsif input.respond_to?(:each)
              '[' + input.map do |object|
                fields.size == 1 ? object[fields.first].to_json : object_to_json(object, fields)
              end.join(',') + ']'
            else
              object_to_json(input, fields)
            end
          end

          def object_to_json(input, fields)
            if input.respond_to?(:as_json)
              options = fields.blank? ? {} : { only: fields }
              input.as_json(options).to_json
            else
              input.to_json
            end
          end

        end

        ::Liquid::Environment.default.register_filter(Json)

      end
    end
  end
end
