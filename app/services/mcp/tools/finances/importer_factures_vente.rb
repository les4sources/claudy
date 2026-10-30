require "digest"

module Mcp
  module Tools
    module Finances
      # Reprendre au registre des ventes un lot de factures émises dans OkiOki
      # (Michael, 2026-10-30). Le connecteur ne lit pas OkiOki : Claude lit le
      # JSON de `/api/me/invoices` et passe les factures par lots, comme
      # `reprendre_pieces` pour Winbooks. Chaque facture passe par
      # `SalesInvoices::Import` : déjà au registre, ignorée ; son écriture de
      # vente déjà au grand livre, rattachée sans nouvelle écriture ; sinon
      # enregistrée et passée au journal Ventes.
      class ImporterFacturesVente < Ecriture
        include Commun

        LOT_MAX = 150
        TYPES = { "facture" => "invoice", "note_de_credit" => "credit_note" }.freeze
        ACTIONS = {
          "attached" => "à rattacher à leur écriture", "recorded" => "à passer au journal Ventes",
          "existing" => "déjà au registre, ignorées", "skipped" => "sans écriture, laissées de côté",
          "refused" => "refusées"
        }.freeze

        tool "importer_factures_vente",
             title: "Reprendre un lot de factures de vente OkiOki",
             description: "Met au registre des ventes un lot de factures émises dans OkiOki (lis le JSON de " \
                          "/api/me/invoices et passe chaque facture : numéro, date, client, total TTC, lignes, taux, " \
                          "communication structurée), #{LOT_MAX} au plus. Dédoublonné par entité et numéro : une facture " \
                          "déjà au registre est ignorée. Si son écriture de vente est déjà au grand livre (reprise " \
                          "Winbooks « 2026:VENTES:2026-078 », ou libellé qui commence par le numéro), elle y est " \
                          "RATTACHÉE sans nouvelle écriture (tiers et lignes lus sur l'écriture, le total doit y " \
                          "correspondre) et les encaissements déjà au 400000 du tiers qui la citent deviennent ses " \
                          "paiements. Sinon elle est enregistrée et passée au journal Ventes (comptes 7 obligatoires : " \
                          "par ligne ou `compte_defaut`), sauf avec `rattacher_seulement`. Chaque facture séparément : " \
                          "un refus n'arrête pas les autres, l'aperçu les liste. Le client se donne par son nom ou #id " \
                          "dans les tiers (voir tiers ; enregistrer_tiers pour un nouveau).",
             schema: {
               properties: {
                 entite: ENTITE.merge(description: "Entité qui a émis les factures (défaut de chaque facture). Défaut : la première active."),
                 compte_defaut: { type: "string", description: "Compte de produit (classe 7) des lignes qui n'en donnent pas." },
                 rattacher_seulement: { type: "boolean", description: "Ne passer aucune écriture : seulement ignorer ou rattacher. Défaut : non." },
                 factures: {
                   type: "array", maxItems: LOT_MAX,
                   items: {
                     type: "object",
                     properties: {
                       numero: { type: "string", description: "Numéro OkiOki (2026-047)." },
                       date: DATE.merge(description: "Date d'émission."),
                       type: { type: "string", enum: TYPES.keys, description: "Défaut : facture." },
                       client: { type: "string", description: "Le tiers client : nom ou #id." },
                       montant: MONTANT.merge(description: "Total TTC en euros, positif même pour une note de crédit."),
                       entite: ENTITE.merge(description: "Facultatif : l'entité de cette facture."),
                       facture_corrigee: { type: "string", description: "Pour une note de crédit : le numéro de la facture corrigée." },
                       communication: { type: "string", description: "Communication structurée (+++123/4567/89012+++)." },
                       notes: { type: "string" },
                       lignes: {
                         type: "array",
                         items: {
                           type: "object",
                           properties: {
                             compte: { type: "string", description: "Compte de produit (classe 7). Défaut : compte_defaut." },
                             libelle: { type: "string" },
                             montant_ht: MONTANT.merge(description: "Montant HTVA en euros."),
                             taux: { type: "integer", enum: SalesInvoiceLine::VAT_RATES },
                             tva: MONTANT.merge(description: "La TVA telle que la facture l'affiche.")
                           },
                           required: %w[montant_ht]
                         }
                       }
                     },
                     required: %w[numero date montant]
                   }
                 }
               },
               required: %w[factures]
             }

        private

        def planifier(arguments)
          factures = Array(arguments["factures"])
          raise Error, "Donne au moins une facture." if factures.empty?
          raise Error, "#{factures.size} factures : #{LOT_MAX} au plus par lot." if factures.size > LOT_MAX

          entite = arguments["entite"].present? ? entite!(arguments["entite"]) : LegalEntity.actives.ordered.first
          compte_defaut = compte_produit!(arguments["compte_defaut"], "compte_defaut") if arguments["compte_defaut"].present?
          lues = factures.each_with_index.map { |f, i| lire(f.to_h, i, entite, compte_defaut) }
          doublons = lues.group_by { |p| [p[:legal_entity]&.id, p[:number]] }.select { |_, v| v.size > 1 }.keys
          raise Error, "Numéro en double dans le lot : #{doublons.map(&:last).join(', ')}." if doublons.any?

          seulement = arguments["rattacher_seulement"] == true
          resultats = simuler { importer(lues, seulement, "claude:#{user.email}") }
          Plan.new(resume: resume(resultats, "Aperçu"),
                   empreinte: [Digest::SHA256.hexdigest([factures, entite.id, compte_defaut&.id, seulement].to_json),
                               resultats.map { |r| [r.piece[:number], r.action] }],
                   donnees: { pieces: lues, rattacher_seulement: seulement })
        end

        def appliquer(plan)
          resume(importer(plan.donnees[:pieces], plan.donnees[:rattacher_seulement], whodunnit), "Fait")
        end

        def importer(pieces, rattacher_seulement, auteur)
          metier! { ::SalesInvoices::Import.new(pieces: pieces, attach_only: rattacher_seulement, whodunnit: auteur).run! }
        end

        # Une facture illisible ne bloque pas le lot : elle revient refusée,
        # avec sa raison. Un client ou une ligne inconnus ne gênent que si la
        # facture doit être passée (un rattachement lit l'écriture).
        def lire(facture, index, entite_defaut, compte_defaut)
          numero = facture["numero"].to_s.strip
          piece = { number: numero.presence || "(facture #{index + 1})", legal_entity: entite_defaut }
          raise Error, "donne son numéro." if numero.empty?

          piece[:legal_entity] = entite!(facture["entite"]) if facture["entite"].present?
          piece[:issued_on] = date!(facture["date"], "date")
          piece[:kind] = facture["type"].present? ? (TYPES[facture["type"].to_s] || raise(Error, "type : #{TYPES.keys.join(', ')}.")) : "invoice"
          piece[:total_cents] = cents!(facture["montant"], "montant").abs
          piece[:credited_number] = facture["facture_corrigee"].to_s.strip.presence
          piece[:payment_reference] = facture["communication"].to_s.strip.presence
          piece[:notes] = facture["notes"].to_s.strip.presence
          lire_client(piece, facture["client"])
          lire_lignes(piece, facture["lignes"], compte_defaut)
          piece
        rescue Base::Error => e
          piece.merge(error: e.message)
        end

        def lire_client(piece, client)
          if client.blank?
            piece[:third_party_error] = "pas de client."
          else
            piece[:third_party] = tiers!(client)
          end
        rescue Base::Error => e
          piece[:third_party_error] = "client « #{client} » : #{e.message}"
        end

        def lire_lignes(piece, lignes, compte_defaut)
          lignes = Array(lignes)
          return piece[:lines_error] = "pas de lignes." if lignes.empty?

          defaut = piece[:legal_entity]&.vat_regime == "subject" ? 21 : 0
          piece[:lines] = lignes.each_with_index.map do |ligne, i|
            ligne = ligne.to_h
            compte = ligne["compte"].present? ? compte_produit!(ligne["compte"], "ligne #{i + 1}") : compte_defaut
            raise Error, "ligne #{i + 1} sans compte de produit (donne-le, ou compte_defaut)." if compte.nil?

            taux = ligne["taux"].presence&.to_i || defaut
            raise Error, "ligne #{i + 1} : taux #{taux} inconnu." unless SalesInvoiceLine::VAT_RATES.include?(taux)

            attributs = { "general_account_id" => compte.id, "label" => ligne["libelle"].to_s.strip.first(250).presence,
                          "net_cents" => cents!(ligne["montant_ht"], "ligne #{i + 1}"), "vat_rate" => taux, "position" => i }
            attributs["typed_vat_cents"] = cents!(ligne["tva"], "ligne #{i + 1}, tva") if ligne["tva"].present?
            attributs
          end
        rescue Base::Error => e
          piece[:lines] = nil
          piece[:lines_error] = e.message
        end

        def compte_produit!(reference, ou)
          compte = compte_general!(reference)
          raise Error, "#{ou} : #{compte} n'est pas un compte de produit (classe 7)." unless compte.klass == 7

          compte
        end

        def resume(resultats, titre)
          lignes = ["#{titre} : #{resultats.size} facture(s) OkiOki."]
          resultats.group_by(&:action).sort_by { |action, _| ACTIONS.keys.index(action) }.each do |action, groupe|
            total = groupe.sum { |r| r.piece[:total_cents].to_i }
            lignes << "#{groupe.size} #{ACTIONS[action]} (#{euros(total)})"
            groupe.first(60).each do |r|
              paiements = r.linked.to_a.any? ? " · #{r.linked.size} encaissement(s) relié(s)" : ""
              lignes << "  - #{r.piece[:number]} · #{r.piece[:issued_on]} · #{euros(r.piece[:total_cents].to_i)} · #{r.detail}#{paiements}"
            end
            lignes << "  …" if groupe.size > 60
          end
          lignes.join("\n")
        end
      end
    end
  end
end
