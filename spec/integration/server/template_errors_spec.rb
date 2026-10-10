require File.dirname(__FILE__) + '/../integration_helper'

require 'locomotive/steam/adapters/filesystem.rb'

describe 'A template error' do

  include Rack::Test::Methods

  def site_files
    {
      'app/views/sections/broken_hero.liquid'  => "---\nname: Broken hero\n---\n<section>\n  {% if true %}\n    hi\n  {% endif\n</section>\n",
      'app/views/sections/card_holder.liquid'  => "---\nname: Card holder\n---\n<div>{% include 'broken_card' %}</div>\n",
      'app/views/snippets/broken_card.liquid'  => "card\n{% if %}\n",
      'app/views/sections/first_block.liquid'  => "---\nname: First block\n---\n<p>first block</p>\n",
      'app/views/sections/second_block.liquid' => "---\nname: Second block\n---\n{% action 'second' %}a.b(+}{% endaction %}\n",
      'app/views/sections/deep_hero.liquid'    => "---\nname: Deep hero\n---\n#{'{% if true %}' * 101}deep#{'{% endif %}' * 101}\n",
      'app/views/pages/broken-hero.liquid'     => "---\nlisted: false\n---\n{% section 'broken_hero' %}\n",
      'app/views/pages/card-holder.liquid'     => "---\nlisted: false\n---\n{% section 'card_holder' %}\n",
      'app/views/pages/two-sections.liquid'    => "---\nlisted: false\n---\n{% section 'first_block' %}{% section 'second_block' %}\n",
      'app/views/pages/after-section.liquid'   => "---\nlisted: false\n---\n{% section 'first_block' %}{% action 'page' %}a.b(+}{% endaction %}\n",
      'app/views/pages/deep-hero.liquid'       => "---\nlisted: false\n---\n{% section 'deep_hero' %}\n",
      'app/views/pages/blocks.liquid'          => "---\nlisted: false\n---\n{% section 'first_block' %}\n",
      'app/views/pages/cycle-a.liquid'         => "---\nhandle: cycle-a\nlisted: false\n---\n{% extends cycle-b %}\n{% block body %}A{% endblock %}\n",
      'app/views/pages/cycle-b.liquid'         => "---\nhandle: cycle-b\nlisted: false\n---\n{% extends cycle-a %}\n{% block body %}B{% endblock %}\n",
      'app/views/pages/self-page.liquid'       => "---\nhandle: self-page\nlisted: false\n---\n{% extends self-page %}\n"
    }
  end

  before(:all) do
    @site_path = Dir.mktmpdir
    FileUtils.cp_r(File.join(default_fixture_site_path, '.'), @site_path)
    site_files.each { |path, content| File.write(File.join(@site_path, path), content) }
  end

  after(:all) do
    FileUtils.remove_entry(@site_path)
    Locomotive::Steam::Adapters::Filesystem::SimpleCacheStore.new.clear
    run_server
  end

  before { Locomotive::Steam::Adapters::Filesystem::SimpleCacheStore.new.clear }

  def app
    Locomotive::Steam.configure do |config|
      config.mode       = :test
      config.adapter    = { name: :filesystem, path: @site_path }
      config.asset_path = File.join(@site_path, 'public')
      config.log_file   = File.join(@site_path, 'log/steam.log')
    end

    Locomotive::Steam::Server.to_app
  end

  def file(path)
    File.join(@site_path, path)
  end

  it 'leaves a page whose sections parse rendered' do
    get '/blocks'

    expect(last_response.status).to eq 200
    expect(last_response.body).to include 'first block'
  end

  it 'in a section names the section, with its code' do
    expect { get '/broken-hero' }.to raise_error(Locomotive::Steam::LiquidError) { |error|
      expect(error.template_name).to eq 'sections--broken_hero'
      expect(error.line_number).to eq 4
      expect(error.code_lines).to include [4, '  {% endif']
    }
  end

  it 'in a snippet a section includes names the snippet, with its code' do
    expect { get '/card-holder' }.to raise_error(Locomotive::Steam::LiquidError) { |error|
      expect(error.template_name).to eq file('app/views/snippets/broken_card.liquid')
      expect(error.code_lines).to include [2, '{% if %}']
    }
  end

  it 'in the second of two sections names the second section' do
    expect { get '/two-sections' }.to raise_error(Locomotive::Steam::TemplateError) { |error|
      expect(error.template_name).to eq 'sections--second_block'
    }
  end

  it 'in a page, after a section, names the page' do
    expect { get '/after-section' }.to raise_error(Locomotive::Steam::TemplateError) { |error|
      expect(error.template_name).to eq file('app/views/pages/after-section.liquid')
    }
  end

  it 'from pages extending each other names the page that closes the loop' do
    expect { get '/cycle-a' }.to raise_error(Locomotive::Steam::LiquidError) { |error|
      expect(error.message).to include 'Pages extend each other in a loop: cycle-a, cycle-b, cycle-a'
      expect(error.template_name).to eq file('app/views/pages/cycle-b.liquid')
      expect(error.code_lines).to include [1, '{% extends cycle-a %}']
    }
  end

  it 'from a page extending itself names the page' do
    expect { get '/self-page' }.to raise_error(Locomotive::Steam::LiquidError) { |error|
      expect(error.message).to include 'Pages extend each other in a loop: self-page, self-page'
      expect(error.template_name).to eq file('app/views/pages/self-page.liquid')
    }
  end

  it 'nested too deep in a section keeps its Liquid class and names the section' do
    expect { get '/deep-hero' }.to raise_error(::Liquid::StackLevelError) { |error|
      expect(error.template_name).to eq 'sections--deep_hero'
    }
  end

end
