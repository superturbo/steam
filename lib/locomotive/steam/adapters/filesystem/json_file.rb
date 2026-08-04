require 'json'

module Locomotive::Steam
  module Adapters
    module Filesystem

      module JsonFile

        module_function

        def blank?(json, path)
          json.blank?
        rescue ArgumentError, EncodingError => e
          raise Locomotive::Steam::JsonParsingError.new(e, path, json)
        end

        def parse(json, path)
          raise ArgumentError, 'invalid byte sequence' unless json.valid_encoding?

          JSON.parse(json, allow_comments: false, allow_duplicate_key: false)
        rescue JSON::ParserError, ArgumentError, EncodingError => e
          raise Locomotive::Steam::JsonParsingError.new(e, path, json)
        end

      end

    end
  end
end
