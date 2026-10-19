require "digest"

module Mcp
  module Tools
    module Finances
      # La reprise d'un ancien logiciel (Winbooks) : des factures d'achat et de
      # vente qui n'existent nulle part ailleurs dans Claudy. Le connecteur ne
      # transporte pas de fichier : Claude lit l'export et passe les pièces par
      # lots. Chaque pièce passe par `Accounting::ImportLedgerDocument`, le
      # même service que la reprise d'août : équilibre contrôlé avant d'écrire,
      # aucun compte ni tiers créé en douce, et une pièce déjà reprise (même
      # référence) n'est jamais doublée.
      #
      # Les paiements de ces factures sont déjà au grand livre (banque, caisse) :
      # une pièce reprise ne touche donc que ses comptes de charge ou de produit
      # et le tiers (440000, 400000), jamais la trésorerie.
      #
      # Le journal « divers » porte les corrections de la reprise elle-même :
      # l'à-nouveau 2025 recopiait le bilan Winbooks alors que 2022-2024 étaient
      # déjà au grand livre (Michael, 2026-10-15). On corrige par une opération
      # diverse, jamais en réécrivant l'à-nouveau. Elle seule peut toucher la
      # trésorerie : l'à-nouveau doublait aussi la caisse (Michael, 2026-10-19).
      class ReprendrePieces < Ecriture
        include Commun

        LOT_MAX = 150
        JOURNAUX = { "achats" => "purchases", "ventes" => "sales", "divers" => "misc" }.freeze
        TRESORERIE = /\A5/

        tool "reprendre_pieces",
             title: "Reprendre des pièces d'un ancien logiciel",
             description: "Reprend au grand livre des factures d'achat ou de vente tenues dans un ancien logiciel " \
                          "(Winbooks), par lots de #{LOT_MAX} pièces au plus. Chaque pièce porte sa référence d'origine " \
                          "(exercice, journal, numéro : « 2024:ACHATS:261 »), sa date, son libellé et ses lignes " \
                          "équilibrées (compte du plan par son CODE EXACT, archivé accepté ; tiers par son code sur la " \
                          "ligne 440000 ou 400000, ou son nom exact). Le journal « divers » porte une correction de la reprise " \
                          "(ex. un à-nouveau qui double des soldes déjà repris). Une pièce déjà reprise est ignorée. Refus d'ensemble si un compte, " \
                          "un tiers ou un exercice ouvert manque, ou si une facture touche la trésorerie (classe 5) : seul le journal « divers » le peut.",
             schema: {
               properties: {
                 source: { type: "string", description: "Logiciel d'origine. Défaut : winbooks." },
                 entite: ENTITE.merge(description: "Entité qui porte les pièces. Défaut : la fondation."),
                 pieces: {
                   type: "array", maxItems: LOT_MAX,
                   items: {
                     type: "object",
                     properties: {
                       ref: { type: "string", description: "Référence d'origine, unique : exercice:journal:numéro." },
                       journal: { type: "string", enum: JOURNAUX.keys },
                       date: DATE,
                       libelle: { type: "string" },
                       lignes: {
                         type: "array",
                         items: {
                           type: "object",
                           properties: {
                             compte: { type: "string", description: "Code exact du compte (601601, 440000…)." },
                             tiers: { type: "string", description: "Code du tiers (ANTARGAZ), ou son nom exact, sur la ligne 440000 ou 400000." },
                             debit: MONTANT, credit: MONTANT,
                             libelle: { type: "string" }
                           },
                           required: %w[compte]
                         }
                       }
                     },
                     required: %w[ref journal date libelle lignes]
                   }
                 }
               },
               required: %w[pieces motif]
             }

        private

        def planifier(arguments)
          motif!(arguments)
          source = arguments["source"].to_s.strip.downcase.presence || "winbooks"
          entite = arguments["entite"].present? ? entite!(arguments["entite"]) : fondation
          pieces = Array(arguments["pieces"])
          raise Error, "Donne au moins une pièce." if pieces.empty?
          raise Error, "#{pieces.size} pièces : #{LOT_MAX} au plus par lot." if pieces.size > LOT_MAX

          Accounting::ImportLedgerDocument.reset_cache!
          lues = pieces.each_with_index.map { |piece, i| lire!(piece, i, source) }
          doublons = lues.group_by { |p| p[:external_ref] }.select { |_, v| v.size > 1 }.keys
          raise Error, "Référence en double dans le lot : #{doublons.join(', ')}." if doublons.any?

          deja = LedgerDocument.where(source_system: source, external_ref: lues.map { |p| p[:external_ref] })
                               .joins(:journal_entries).distinct.pluck(:external_ref).to_set
          nouvelles = lues.reject { |p| deja.include?(p[:external_ref]) }
          tiers_par_code!(nouvelles)
          controler!(nouvelles, entite)

          Plan.new(resume: resume(lues, nouvelles, deja, entite, source),
                   empreinte: [source, entite.id, deja.to_a.sort, Digest::SHA256.hexdigest(nouvelles.to_json)],
                   donnees: { source: source, entite_id: entite.id, pieces: nouvelles })
        end

        def appliquer(plan)
          entite = LegalEntity.find(plan.donnees[:entite_id])
          Accounting::ImportLedgerDocument.reset_cache!
          ecritures = plan.donnees[:pieces].map do |piece|
            metier! do
              Accounting::ImportLedgerDocument.new(
                legal_entity: entite, source_system: plan.donnees[:source], external_ref: piece[:external_ref],
                journal: piece[:journal], entry_date: piece[:date], label: piece[:libelle],
                lines: piece[:lignes], payload: piece[:brut], whodunnit: whodunnit
              ).run!
            end
          end
          return "Rien à reprendre : toutes les pièces du lot l'étaient déjà." if ecritures.empty?

          "#{ecritures.size} pièce(s) reprise(s) au grand livre de #{entite.name} : " \
            "#{ecritures.first.reference} → #{ecritures.last.reference}."
        end

        def lire!(piece, index, source)
          ref = piece["ref"].to_s.strip
          raise Error, "Pièce #{index + 1} : donne sa référence d'origine." if ref.empty?

          journal = JOURNAUX[piece["journal"].to_s] || raise(Error, "#{ref} : journal « achats », « ventes » ou « divers ».")
          libelle = piece["libelle"].to_s.strip.presence || raise(Error, "#{ref} : donne un libellé.")
          lignes = Array(piece["lignes"]).each_with_index.map { |ligne, i| ligne!(ligne, "#{ref}, ligne #{i + 1}") }
          raise Error, "#{ref} : une pièce a au moins deux lignes." if lignes.size < 2

          { external_ref: "#{source}:#{ref}", ref: ref, journal: journal, date: date!(piece["date"], "#{ref} : date"),
            libelle: libelle.first(250), lignes: lignes, brut: piece.to_h }
        end

        def ligne!(ligne, ou)
          debit = ligne["debit"].present? ? cents!(ligne["debit"], ou).abs : 0
          credit = ligne["credit"].present? ? cents!(ligne["credit"], ou).abs : 0
          raise Error, "#{ou} : un débit OU un crédit." unless debit.zero? ^ credit.zero?

          { account_code: ligne["compte"].to_s.strip, third_party_code: ligne["tiers"].to_s.strip.presence,
            debit_cents: debit, credit_cents: credit, label: ligne["libelle"].to_s.strip.first(250).presence }
        end

        # Un tiers se donne par son code ; à défaut, par son nom exact. C'est ce
        # qui permet de reprendre les factures d'un tiers créé pour l'occasion,
        # dont le code dérivé du nom diffère de celui de l'ancien logiciel.
        def tiers_par_code!(pieces)
          references = pieces.flat_map { |p| p[:lignes].filter_map { |l| l[:third_party_code] } }.uniq
          codes = ThirdParty.where(code: references).pluck(:code).to_set
          correspondances = (references - codes.to_a).to_h do |reference|
            trouves = ThirdParty.where("LOWER(name) = ?", reference.downcase).pluck(:code)
            [reference, trouves.one? ? trouves.first : reference]
          end
          pieces.each { |p| p[:lignes].each { |l| l[:third_party_code] = correspondances.fetch(l[:third_party_code], l[:third_party_code]) } }
        end

        # Tout ce qui ferait échouer une pièce, pour le lot entier, AVANT
        # d'écrire : on corrige la liste en une fois, pas pièce après pièce.
        def controler!(pieces, entite)
          comptes = GeneralAccount.where(code: pieces.flat_map { |p| p[:lignes].map { |l| l[:account_code] } }.uniq).index_by(&:code)
          tiers = ThirdParty.where(code: pieces.flat_map { |p| p[:lignes].filter_map { |l| l[:third_party_code] } }.uniq).pluck(:code).to_set
          erreurs = []
          pieces.each do |p|
            debit = p[:lignes].sum { |l| l[:debit_cents] }
            credit = p[:lignes].sum { |l| l[:credit_cents] }
            erreurs << "#{p[:ref]} : déséquilibrée (#{euros(debit)} au débit, #{euros(credit)} au crédit)" if debit != credit
            exercice = entite.fiscal_year_for(p[:date])
            erreurs << "#{p[:ref]} : aucun exercice ne couvre le #{p[:date]}" if exercice.nil?
            erreurs << "#{p[:ref]} : l'exercice #{exercice.label} est clôturé" if exercice && exercice.status != "open"
            p[:lignes].each do |l|
              erreurs << "#{p[:ref]} : compte #{l[:account_code]} absent du plan" unless comptes[l[:account_code]]
              erreurs << "#{p[:ref]} : compte de trésorerie #{l[:account_code]}, déjà au grand livre" if p[:journal] != "misc" && l[:account_code].match?(TRESORERIE)
              erreurs << "#{p[:ref]} : tiers #{l[:third_party_code]} inconnu" if l[:third_party_code] && !tiers.include?(l[:third_party_code])
            end
          end
          return if erreurs.empty?

          raise Error, "Lot refusé, rien n'est écrit (#{erreurs.size} problème(s)) :\n" +
                       erreurs.first(40).map { |e| "  - #{e}" }.join("\n") + (erreurs.size > 40 ? "\n  …" : "")
        end

        def resume(lues, nouvelles, deja, entite, source)
          lignes = ["Reprise #{source} dans le grand livre de #{entite.name} : #{lues.size} pièce(s), " \
                    "#{nouvelles.size} à reprendre, #{deja.size} déjà reprise(s) et ignorée(s)."]
          return lignes.join("\n") if nouvelles.empty?

          dates = nouvelles.map { |p| p[:date] }
          lignes << "Du #{dates.min} au #{dates.max}."
          nouvelles.group_by { |p| p[:journal] }.each do |journal, groupe|
            total = groupe.sum { |p| p[:lignes].sum { |l| l[:debit_cents] } }
            lignes << "Journal #{JournalEntry::JOURNAL_LABELS[journal]} : #{groupe.size} pièce(s), #{euros(total)}."
          end
          lignes << "Soldes par classe (débit − crédit) :"
          soldes = Hash.new(0)
          nouvelles.each { |p| p[:lignes].each { |l| soldes[l[:account_code][0]] += l[:debit_cents] - l[:credit_cents] } }
          soldes.sort.each { |classe, cents| lignes << "  classe #{classe} : #{euros(cents)}" }
          archives = GeneralAccount.where(active: false, code: nouvelles.flat_map { |p| p[:lignes].map { |l| l[:account_code] } }.uniq).count
          lignes << "#{archives} compte(s) archivé(s) utilisé(s), repris tels quels." if archives.positive?
          lignes.join("\n")
        end

        def fondation
          LegalEntity.actives.ordered.find_by("name ILIKE ?", "%fondation%") || LegalEntity.actives.ordered.first ||
            raise(Error, "Aucune entité juridique.")
        end
      end
    end
  end
end
