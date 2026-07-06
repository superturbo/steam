module Locomotive
  module Steam
    module Liquid
      module Tags

        class Hybrid < ::Liquid::Block

          def render_as_block?
            @render_as_block
          end

          def parse(tokens)
            if @render_as_block = find_block_delimiter?(tokens)
              super
            else
              @body  = nil
              @blank = false
            end
          end

          def find_block_delimiter?(tokenizer)
            # Liquid 5 tracks tokenizer progress with an offset.
            # FullToken's tag name is the second capture group.
            tokens = tokenizer.instance_variable_get(:@tokens) || []
            offset = tokenizer.instance_variable_get(:@offset) || 0

            tokens.drop(offset).each do |token|
              next if token.empty?
              if token.start_with?(::Liquid::BlockBody::TAGSTART)
                if token =~ ::Liquid::BlockBody::FullToken
                  return false  if Regexp.last_match(2) == @tag_name
                  return true   if Regexp.last_match(2) == block_delimiter
                end
              end
            end
            false
          end

          def nodelist
            @body&.nodelist || []
          end

        end

      end
    end
  end
end
