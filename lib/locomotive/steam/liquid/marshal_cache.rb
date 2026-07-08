require 'strscan'

module Locomotive
  module Steam
    module Liquid
      # Marshal support for parsed templates, so that consumers (e.g. the
      # engine's LiquidParserWithCacheService) can store them in a cache.
      #
      # Liquid 5 parse-time state holds objects Marshal cannot dump:
      # ParseContext carries a StringScanner and the Environment (whose
      # strainer is an anonymous class), and the parse options injected by
      # Steam reference live services. These hooks strip that state on dump
      # and rebuild it on load.
      #
      # Contract: marshal_load always rebinds to Liquid::Environment.default,
      # where Steam registers its tags and filters. Templates parsed against a
      # custom Liquid::Environment intentionally lose that environment on load.
      module MarshalCache

        # option values injected at parse time, plus the Environment merged in
        # by Liquid::Template#configure_options
        UNMARSHALABLE_OPTION_KEYS = %i(
          parser page parent_finder snippet_finder section_finder environment
        ).freeze

        module Template

          def marshal_dump
            (instance_variables - [:@environment]).map do |ivar|
              value = instance_variable_get(ivar)
              value = value.reject { |key, _| UNMARSHALABLE_OPTION_KEYS.include?(key) } if ivar == :@options && value.is_a?(Hash)
              [ivar, value]
            end
          end

          def marshal_load(ivars)
            ivars.each { |name, value| instance_variable_set(name, value) }
            @environment = ::Liquid::Environment.default
          end

        end

        module ParseContext

          # parse-time machinery rebuilt on load (see marshal_load)
          TRANSIENT_IVARS   = %i(@string_scanner @expression_cache @environment).freeze
          OPTION_HASH_IVARS = %i(@template_options @options @partial_options).freeze

          def marshal_dump
            # @options and @template_options share a hash outside partials;
            # preserve that identity after filtering.
            filtered = {}
            (instance_variables - TRANSIENT_IVARS).map do |ivar|
              value = instance_variable_get(ivar)
              if OPTION_HASH_IVARS.include?(ivar) && value.is_a?(Hash)
                value = filtered[value.object_id] ||=
                  value.reject { |key, _| UNMARSHALABLE_OPTION_KEYS.include?(key) }
              end
              [ivar, value]
            end
          end

          def marshal_load(ivars)
            ivars.each { |name, value| instance_variable_set(name, value) }
            # cache hits re-enter the parser at render time (PartialCache loads
            # snippet/section templates through this very context)
            @environment      = ::Liquid::Environment.default
            @string_scanner   = StringScanner.new(''.dup)
            @expression_cache = {}
          end

        end

      end
    end
  end
end

::Liquid::Template.prepend(Locomotive::Steam::Liquid::MarshalCache::Template)
::Liquid::ParseContext.prepend(Locomotive::Steam::Liquid::MarshalCache::ParseContext)
