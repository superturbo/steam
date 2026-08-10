require 'prism'

require_relative '../../../adapters/query'

module Locomotive
  module Steam
    module Liquid
      module Tags
        module Concerns

          # Parses the Ruby-like attributes DSL of the with_scope tag (e.g.
          # `a: 1, providers.in: ['acme'], title: /foo/i, ref: some.var`) with
          # Prism. Fail-closed: anything outside the accepted node set raises
          # Liquid::SyntaxError.
          module AttributesParser
            extend ActiveSupport::Concern

            included do
              OPERATORS = Locomotive::Steam::Adapters::Query::Operators::PUBLIC.map(&:to_s).freeze

              SYMBOL_OPERATORS_REGEXP = /(\w+\.(#{OPERATORS.join('|')})){1}\s*\:/o
            end

            def parse_markup(markup)
              body = ::Prism.parse("{#{clean_markup(markup)}}").then do |r|
                r.success? ? r.value.statements.body : []
              end

              unless body.size == 1 && body.first.is_a?(::Prism::HashNode)
                raise ::Liquid::SyntaxError, "Invalid attributes syntax: #{markup}"
              end

              visit_hash(body.first, criteria: true)
            end

            private

            def clean_markup(markup)
              # convert symbol operators into valid ruby code
              markup.gsub(SYMBOL_OPERATORS_REGEXP, ':"\1" =>')
            end

            def visit(node)
              case node
              when ::Prism::HashNode               then visit_hash(node)
              when ::Prism::ArrayNode              then node.elements.map { |e| visit(e) }
              when ::Prism::SymbolNode             then node.unescaped.to_sym
              when ::Prism::StringNode             then string_value(node)
              when ::Prism::IntegerNode            then node.value
              when ::Prism::FloatNode              then node.value
              when ::Prism::TrueNode               then true
              when ::Prism::FalseNode              then false
              when ::Prism::RegularExpressionNode  then visit_regexp(node)
              when ::Prism::CallNode               then visit_call(node)
              else
                unsupported!
              end
            end

            # Only the markup itself lists criteria; a hash nested under one is
            # an ordinary value.
            def visit_hash(node, criteria: false)
              seen = {}

              node.elements.each_with_object({}) do |element, hash|
                unsupported! unless element.is_a?(::Prism::AssocNode)

                key  = visit(element.key)
                name = key.to_s

                duplicate!(name) if seen.key?(name)
                seen[name] = true

                invalid_all_value!(name) if criteria && removed_all_form?(name, element.value)

                hash[key] = visit(element.value)
              end
            end

            # `+value` and `left + right` decode to the (left) operand (no
            # arithmetic); anything else must be a bare/dotted variable lookup.
            def visit_call(node)
              unsupported! if node.safe_navigation? || !node.block.nil?

              if node.receiver && node.name == :+@ && node.arguments.nil?
                return visit(node.receiver)
              end

              if node.receiver && node.name == :+ && node.arguments&.arguments&.size == 1
                visit(node.arguments.arguments.first) # validate the right operand, then drop it
                return visit(node.receiver)
              end

              unsupported! unless node.arguments.nil?

              ::Liquid::Expression.parse(variable_path(node).join('.'))
            end

            def variable_path(node)
              receiver = node.receiver

              if receiver.nil?
                [node.name.to_s]
              elsif variable_chain?(receiver)
                variable_path(receiver) << node.name.to_s
              else
                unsupported!
              end
            end

            def variable_chain?(node)
              node.is_a?(::Prism::CallNode) && !node.safe_navigation? &&
                node.arguments.nil? && node.block.nil?
            end

            REGEXP_SHAPE = %r{\A/[^/]+/[imx]*\z}.freeze

            private_constant :REGEXP_SHAPE

            # Reject the removed quoted-regexp form instead of treating it as text.
            def string_value(node)
              value = node.unescaped

              if value.match?(REGEXP_SHAPE)
                raise ::Liquid::SyntaxError, 'A with_scope regexp must be a literal, not a quoted string'
              end

              value
            end

            # Only i/m/x flags are supported; encoding (u/e/s/n) and once (o)
            # flags are rejected, and an invalid pattern is reported as a syntax
            # error rather than leaking a RegexpError.
            def visit_regexp(node)
              if node.once? || node.utf_8? || node.euc_jp? || node.windows_31j? || node.ascii_8bit?
                unsupported!
              end

              options = 0
              options |= Regexp::IGNORECASE if node.ignore_case?
              options |= Regexp::MULTILINE  if node.multi_line?
              options |= Regexp::EXTENDED   if node.extended?

              begin
                Regexp.new(node.unescaped, options)
              rescue RegexpError
                unsupported!
              end
            end

            REMOVED_ALL_FORM = /\A\s*\$and\s*:/

            private_constant :REMOVED_ALL_FORM

            # Left as an ordinary string, the removed `all: "$and: [...]"` form
            # would match nothing at all.
            def removed_all_form?(name, node)
              name.end_with?('.all') && node.is_a?(::Prism::StringNode) &&
                REMOVED_ALL_FORM.match?(node.unescaped)
            end

            def invalid_all_value!(name)
              raise ::Liquid::SyntaxError, "Invalid value for #{name}"
            end

            def duplicate!(key)
              raise ::Liquid::SyntaxError, "Duplicate with_scope key: #{key}"
            end

            def unsupported!
              raise ::Liquid::SyntaxError, 'Unsupported with_scope attribute expression'
            end
          end
        end
      end
    end
  end
end
