module Mcp
  module Tools
    module Guide
      # Une page du Guide, son contenu Markdown complet et son historique
      # (Guide::PagesController#show, Guide::RevisionsController).
      class PageGuide < Base
        include Commun

        tool "page_guide",
             title: "Lire une page du Guide",
             description: "Rend une page du Guide des 4 Sources en entier (Markdown), avec son chapitre, son dernier " \
                          "éditeur et ses contributeur·rices. Avec `historique` : la liste de ses versions. Avec " \
                          "`version` : le contenu de cette version passée. Lis toujours la page avant de la modifier.",
             schema: {
               properties: {
                 page: PAGE,
                 historique: { type: "boolean", description: "Lister les versions (qui, quand, depuis où, ce qui a changé)." },
                 version: { type: "integer", minimum: 1, description: "Numéro de version à lire (1 = la création)." }
               },
               required: %w[page]
             }

        def call(arguments)
          page = page!(arguments["page"])
          return historique(page) if arguments["historique"]
          return version(page, arguments["version"].to_i) if arguments["version"].present?

          contributeurs = page.contributors.map(&:display_name)
          [
            "#{ligne_page(page)}",
            "Chapitre ##{page.chapter.id} « #{page.chapter.title} » · #{page.revisions.size} version(s)",
            ("Contributeur·rices : #{contributeurs.join(', ')}" if contributeurs.any?),
            "Adresse : #{lien_page(page)}",
            "",
            "--- Contenu (Markdown) ---",
            page.body.presence || "(page vide)"
          ].compact.join("\n")
        end

        private

        def historique(page)
          revisions = page.revisions.includes(user: :human).to_a
          lignes = revisions.each_with_index.map do |revision, index|
            numero = revisions.size - index
            "v#{numero} · #{I18n.l(revision.created_at, format: '%d/%m/%Y %H:%M')} · #{revision.author_name}" \
              "#{' (via Claude)' if revision.via_claude?}#{" — #{revision.summary}" if revision.summary.present?}" \
              "#{' [actuelle]' if index.zero?}"
          end
          "Historique de la page ##{page.id} « #{page.title} » :\n#{lignes.join("\n")}"
        end

        def version(page, numero)
          revisions = page.revisions.reorder(:created_at, :id).to_a
          revision = revisions[numero - 1] if numero.positive?
          raise Error, "La page ##{page.id} n'a que #{revisions.size} version(s)." if revision.nil?

          "Version #{numero} de la page ##{page.id}, du #{I18n.l(revision.created_at, format: '%d/%m/%Y %H:%M')} " \
            "par #{revision.author_name} — titre « #{revision.title} »\n\n--- Contenu (Markdown) ---\n#{revision.body.presence || '(vide)'}"
        end
      end
    end
  end
end
