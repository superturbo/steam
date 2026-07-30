require 'prism'
require 'psych'

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

                  key = visit(element.key)
                  hash[key] = visit_assoc_value(key, element.value)
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

            LEGACY_ALL_LIST = /\A\s*\$and\s*:/

            private_constant :LEGACY_ALL_LIST

            # The documented many-to-many form is `all: "$and: ['A', 'B']"`. It
            # is a static markup literal, so it is decoded once here rather than
            # on every render, and a runtime value never reaches the parser.
            def visit_assoc_value(key, node)
              return visit(node) unless node.is_a?(::Prism::StringNode) &&
                                        key.to_s.end_with?('.all') &&
                                        node.unescaped.match?(LEGACY_ALL_LIST)

              legacy_all_list(node.unescaped)
            end

            # Validated on the YAML AST: safe_load alone would silently keep the
            # last of two $and keys and read only the first of two documents.
            def legacy_all_list(source)
              documents = ::Psych.parse_stream(source).children
              mapping   = documents.first.children.first if documents.size == 1

              invalid_all!(source) unless mapping.is_a?(::Psych::Nodes::Mapping) && mapping.children.size == 2

              key, sequence = mapping.children

              invalid_all!(source) unless untagged_scalar?(key) && key.value == '$and'
              invalid_all!(source) unless sequence.is_a?(::Psych::Nodes::Sequence) && untagged?(sequence)
              invalid_all!(source) unless sequence.children.all? { |node| untagged_scalar?(node) }

              sequence.to_ruby.tap do |list|
                invalid_all!(source) unless list.all? { |e| e.is_a?(String) || e.is_a?(Integer) }
              end
            rescue ::Psych::Exception
              invalid_all!(source)
            end

            def untagged_scalar?(node)
              node.is_a?(::Psych::Nodes::Scalar) && untagged?(node)
            end

            def untagged?(node)
              node.tag.nil? || node.tag.empty?
            end

            def invalid_all!(source)
              raise ::Liquid::SyntaxError, "Invalid all syntax: #{source}"
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
