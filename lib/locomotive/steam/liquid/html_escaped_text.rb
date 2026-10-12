require 'cgi'

module Locomotive
  module Steam
    module Liquid

      # A request parameter or a safe_url result keeps its raw text behind the
      # escaped string, so generated HTML escapes it once, unless the string changed.
      class HtmlEscapedText < String

        def self.original(value)
          (value.is_a?(self) && value.original) || value
        end

        def self.escape(value)
          CGI.escapeHTML(original(value).to_s)
        end

        def self.map(value)
          text = value.is_a?(self) && value.original
          text ? new(yield(text)) : yield(value)
        end

        def initialize(text)
          @original = text.to_s.dup.freeze
          super(CGI.escapeHTML(@original))
        end

        def original
          @original.dup if self == CGI.escapeHTML(@original)
        end

      end

    end
  end
end
