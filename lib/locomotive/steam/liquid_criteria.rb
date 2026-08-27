module Locomotive::Steam

  # Criteria entering through Liquid: the repository vets their names against
  # the schema. A plain Hash is the trusted Ruby surface.
  LiquidCriteria = Data.define(:attributes) do
    def self.wrap(attributes)
      new(attributes: attributes.dup)
    end
  end

end
