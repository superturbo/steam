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

              visit(body.first)
            end

            private

            def clean_markup(markup)
              # convert symbol operators into valid ruby code
              markup.gsub(SYMBOL_OPERATORS_REGEXP, ':"\1" =>')
            end

            def visit(node)
              case node
              when ::Prism::HashNode
                node.elements.each_with_object({}) do |element, hash|
                  unsupported! unless element.is_a?(::Prism::AssocNode)

                  hash[visit(element.key)] = visit(element.value)
                end
              when ::Prism::ArrayNode              then node.elements.map { |e| visit(e) }
              when ::Prism::SymbolNode             then node.unescaped.to_sym
              when ::Prism::StringNode             then node.unescaped
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

            def unsupported!
              raise ::Liquid::SyntaxError, 'Unsupported with_scope attribute expression'
            end
          end
        end
      end
    end
  end
end
