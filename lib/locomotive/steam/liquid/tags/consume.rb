module Locomotive
  module Steam
    module Liquid
      module Tags

        # Consume web services as easy as pie directly in liquid!
        #
        # Usage:
        #
        # {% consume blog from 'http://nocoffee.tumblr.com/api/read.json?num=3' username: 'john', password: 'easy', format: 'json', expires_in: 3000 %}
        #   {% for post in blog.posts %}
        #     {{ post.title }}
        #   {% endfor %}
        # {% endconsume %}
        #
        class Consume < ::Liquid::Block

          include Concerns::SimpleAttributesParser

          Syntax = /(#{::Liquid::VariableSignature}+)\s*from\s*(#{::Liquid::QuotedFragment}+),?(.+)?/o.freeze

          attr_reader :variable_name, :url_expr, :url, :expires_in

          def initialize(tag_name, markup, options)
            super

            if markup =~ Syntax
              @variable_name, @url_expr, attributes = $1.to_s, ::Liquid::Expression.parse($2), $3

              parse_attributes(attributes)
            else
              raise ::Liquid::SyntaxError.new("Syntax Error in 'consume' - Valid syntax: consume <var> from \"<url>\" [username: value, password: value]")
            end
          end

          def render(context)
            evaluate_attributes(context)

            # attributes will become the options which will be passed to the service.
            # we don't want the expires_in option to be part of it.
            @expires_in = attributes.delete(:expires_in)&.to_i

            # the URL can come from a variable
            @url = context.evaluate(url_expr)

            if url.blank?
              Locomotive::Common::Logger.error "A consume tag can't call an empty URL."
              ''
            else
              context.stack do
                context.scopes.last[variable_name] = response(context)
                super(context)
              end
            end
          end

          protected

          def response(context)
            site_id = context.registers[:site]&._id
            return call_service(context) unless expires_in.to_i > 0 && site_id

            cache_service(context).fetch(cache_key(site_id), expires_in: expires_in, skip_nil: true) { call_service(context) }
          end

          def call_service(context)
            Locomotive::Common::Logger.info "[consume] #{loggable_call(context)}"

            service(context).consume(url, attributes)
          rescue *HTTParty::COMMON_NETWORK_ERRORS => error
            Locomotive::Common::Logger.error "[consume] #{(attributes[:method] || 'GET').to_s.upcase} " \
              "#{Locomotive::Steam::LogFilter.url(url, host_log_rules(context))} failed (#{error.class})"
            nil
          end

          def cache_key(site_id)
            "steam/consume/#{site_id}/#{Digest::SHA256.hexdigest([url, attributes, expires_in].to_json)}"
          end

          def service(context)
            context.registers[:services].external_api
          end

          # Filtered by name: a value under a name no rule covers, or a token in the path, stays.
          def loggable_call(context)
            rules = host_log_rules(context)
            "#{Locomotive::Steam::LogFilter.url(url, rules)} / #{Locomotive::Steam::LogFilter.params(attributes, rules).inspect}"
          end

          def host_log_rules(context)
            Array(context.registers[:request]&.env&.fetch('action_dispatch.parameter_filter', nil))
          end

          def cache_service(context)
            context.registers[:services].cache
          end

        end

        ::Liquid::Environment.default.register_tag('consume'.freeze, Consume)
      end
    end
  end
end