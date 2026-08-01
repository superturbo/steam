module AdapterParityFixture

  # Reads this fixture's YAML front matter and template body.
  module WagonTemplate

    FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

    module_function

    def read(file)
      match = File.read(file).match(FRONT_MATTER)

      raise Error, "#{File.basename(file)} has no front matter" if match.nil?

      [YAML.safe_load(match[1], aliases: false) || {}, match[2]]
    end

  end

end
