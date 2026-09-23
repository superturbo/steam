require 'prism'

require_relative '../../../adapters/query'

module Locomotive
  module Steam
    module Liquid
      module Tags
        module Concerns

          # Parses the Ruby-like attributes DSL of the with_scope tag (e.g.
          # `a: 1, providers.in: ['acme'], ref: some.var`) with Prism.
          # Fail-closed: anything outside the accepted node set raises
          # Liquid::SyntaxError.
          module AttributesParser
            extend ActiveSupport::Concern

            OPERATORS = Locomotive::Steam::Adapters::Query::Operators::PUBLIC.map(&:to_s).freeze

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

            # Rewrites operator keys without changing quoted text.
            def clean_markup(markup)
              operator_keys(markup).reverse_each do |from, to, name|
                replacement = %(:"#{name}" =>).force_encoding(markup.encoding)

                markup = markup.byteslice(0, from) + replacement + markup.byteslice(to..-1)
              end

              markup
            end

            # Prism offsets count bytes, so the splice above does too.
            def operator_keys(markup)
              tokens = ::Prism.lex(markup).value.map(&:first)

              tokens.each_index.with_object([]) do |index, keys|
                field, dot, operator = tokens[index, 3]
                next unless operator_key?(field, dot, operator)

                colon = colon_after(tokens, index + 3)
                next if colon.nil?

                # Prism may include an adjacent value's opening quote in
                # SYMBOL_BEGIN, so only the colon itself makes way.
                keys << [field.location.start_offset,
                         colon.location.start_offset + 1,
                         "#{field.value}.#{operator.value}"]
              end
            end

            # Prism may classify schema names as constants or ruby keywords.
            FIELD_NAME = /\A\w+\z/

            COLONS = %i(COLON SYMBOL_BEGIN).freeze

            NEWLINES = %i(NEWLINE IGNORED_NEWLINE).freeze

            private_constant :FIELD_NAME, :COLONS, :NEWLINES

            # Nothing separates the field from its operator.
            def operator_key?(field, dot, operator)
              return false if operator.nil?

              FIELD_NAME.match?(field.value.to_s) && dot.type == :DOT &&
                operator.type == :IDENTIFIER && OPERATORS.include?(operator.value) &&
                field.location.end_offset == dot.location.start_offset &&
                dot.location.end_offset == operator.location.start_offset
            end

            def colon_after(tokens, index)
              index += 1 while NEWLINES.include?(tokens[index]&.type)

              tokens[index] if COLONS.include?(tokens[index]&.type)
            end

            def visit(node)
              case node
              when ::Prism::HashNode               then visit_hash(node)
              when ::Prism::ArrayNode              then node.elements.map { |e| visit(e) }
              when ::Prism::SymbolNode             then node.unescaped.to_sym
              when ::Prism::StringNode             then node.unescaped
              when ::Prism::IntegerNode            then node.value
              when ::Prism::FloatNode              then node.value
              when ::Prism::TrueNode               then true
              when ::Prism::FalseNode              then false
              when ::Prism::NilNode                then nil
              when ::Prism::RegularExpressionNode
                raise ::Liquid::SyntaxError, 'regular expression literals are not supported in with_scope'
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
