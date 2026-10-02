require 'uri'
require 'active_support/parameter_filter'

module Locomotive
  module Steam

    module LogFilter

      # Common secret name parts, plus Steam's sign-in id, API auth options and headers.
      PARAMETERS = %i(passw email secret token _key crypt salt certificate otp ssn cvv cvc auth_id header_auth authorization headers).freeze

      module_function

      def filtering_enabled?
        Locomotive::Steam.configuration.mode != :test
      end

      def params(hash, extra = [])
        filtering_enabled? ? filter(extra).filter(hash) : hash
      end

      # Decode query names for filtering while preserving their original spelling. Omit fragments and mask userinfo.
      def url(string, extra = [])
        string = string.to_s
        return string unless filtering_enabled?

        URI.parse(string)

        filter        = filter(extra)
        address, query = string.split('#', 2).first.split('?', 2)
        address       = address.sub(%r{\A((?:[a-z][a-z\d+.-]*:)?//)?[^/?#@]*@}i) { "#{$1}[FILTERED]@" }

        return address unless query

        "#{address}?#{query.gsub(/([^&;=]+)=([^&;]*)/) { "#{$1}=#{filtered_value(filter, $1, $2)}" }}"
      rescue URI::InvalidURIError
        'an unparsable URL'
      end

      # A name that decodes to invalid UTF-8 cannot be matched, so the URL is not written.
      def filtered_value(filter, name, value)
        name = URI.decode_www_form_component(name)
        raise URI::InvalidURIError unless name.valid_encoding?

        filter.filter(name => value)[name]
      end

      def filter(extra)
        ActiveSupport::ParameterFilter.new(PARAMETERS + Array(extra))
      end

    end

  end
end
