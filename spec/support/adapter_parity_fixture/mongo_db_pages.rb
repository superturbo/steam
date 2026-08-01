module AdapterParityFixture

  # Compiles the fixture's page files into the documents Engine would persist.
  module MongoDBPages

    module_function

    def documents
      WagonPages.all.map { |page| document(page) }
    end

    def page_id(path)
      WagonSite.oid("page:#{path}")
    end

    def document(page)
      path   = page[:path]
      parent = WagonPages.parent_path(path)

      {
        '_id'          => page_id(path),
        'site_id'      => WagonSite.site_id,
        'title'        => localized(page[:titles]),
        'slug'         => localized(page[:slugs]),
        'fullpath'     => localized_fullpath(path),
        'raw_template' => localized(page[:bodies]),
        'depth'        => WagonPages.depth(path),
        'position'     => page[:attributes].fetch('position'),
        'listed'       => page[:attributes].fetch('listed'),
        'published'    => page[:attributes].fetch('published'),
        'parent_ids'   => ancestors(path).map { |ancestor| page_id(ancestor) }
      }.tap do |document|
        document['parent_id'] = page_id(parent) if parent
        document['handle']    = page[:attributes]['handle'] if page[:attributes].key?('handle')
      end
    end

    def localized_fullpath(path)
      WagonSite.locales.to_h { |locale| [locale, fullpath_for(path, locale)] }
    end

    def fullpath_for(path, locale)
      slug   = slug_for(path, locale)
      parent = WagonPages.parent_path(path)

      return slug if parent.nil? || parent == WagonPages::ROOT

      "#{fullpath_for(parent, locale)}/#{slug}"
    end

    def slug_for(path, locale)
      slugs = WagonPages.page(path)[:slugs]

      slugs.fetch(locale.to_sym) { slugs.fetch(WagonSite.default_locale) }
    end

    def ancestors(path)
      parent = WagonPages.parent_path(path)

      parent.nil? ? [] : ancestors(parent) + [parent]
    end

    # A locale the fixture does not override falls back to the default one, the
    # way a Wagon site without a translated file renders.
    def localized(values)
      WagonSite.locales.to_h do |locale|
        [locale, values.fetch(locale.to_sym) { values.fetch(WagonSite.default_locale) }]
      end
    end

  end

end
