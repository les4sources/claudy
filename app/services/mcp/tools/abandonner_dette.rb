module Mcp
  module Tools
    # `abandon-bar-2024-2025.rb`, pour n'importe quel poste et n'importe quelle
    # date : ce qui reste dû sur un poste jusqu'à une date est éteint par UNE
    # écriture d'abandon par compte. Rien n'est supprimé ; l'abandon se lit
    # dans le grand livre. Rejouer ne double rien (clé par compte, poste, date).
    class AbandonnerDette < Ecriture
      tool "abandonner_dette",
           title: "Abandonner une dette ancienne",
           description: "Éteint ce qui reste dû sur un poste pour des lignes datées au plus tard d'une date (ex. bar " \
                        "jusqu'au 2025-12-31, comptes clôturés), par une écriture d'abandon par compte. Sans compte : " \
                        "tous les comptes actifs. Rien n'est supprimé.",
           schema: {
             properties: {
               poste: POSTE,
               jusqu_au: DATE.merge(description: "Dernière date de dette abandonnée (AAAA-MM-JJ). L'écriture est datée de ce jour."),
               compte: COMPTE.merge(description: "Code ou nom d'UN compte. Absent : tous les comptes actifs."),
               libelle: { type: "string", description: "Libellé de l'écriture (par défaut « Abandon — <poste> jusqu'au <date> »)." }
             },
             required: %w[poste jusqu_au motif]
           }

      private

      def planifier(arguments)
        motif!(arguments)
        flow = poste!(arguments["poste"])
        limite = date!(arguments["jusqu_au"], "jusqu_au")
        libelle = arguments["libelle"].to_s.strip.presence ||
                  "Abandon — #{AccountEntry::FLOW_LABELS[flow].downcase} jusqu'au #{I18n.l(limite)}"
        comptes = arguments["compte"].present? ? [compte!(arguments["compte"])] : MemberAccount.actives.ordered.to_a

        abandons = comptes.filter_map do |compte|
          lignes = MemberAccounts::Outstanding.new(compte).poste(flow)&.lignes.to_a.select { |l| l.entry_date <= limite }
          du = lignes.sum(&:amount_cents)
          cle = "abandon:#{flow}:#{limite.iso8601}:#{compte.id}"
          next unless du.positive?
          next if AccountEntry.with_deleted { AccountEntry.exists?(idempotency_key: cle) }

          mois = lignes.map { |l| l.entry_date.strftime("%m/%Y") }.uniq
          { compte: compte, du: du, mois: mois,
            attrs: { member_account_id: compte.id, entry_date: limite, amount_cents: -du, flow: flow, kind: "reversal",
                     source: "abandon", idempotency_key: cle, label: libelle.first(250) } }
        end
        raise Error, "Rien à abandonner : aucune dette #{AccountEntry::FLOW_LABELS[flow]} ouverte au #{limite} (ou abandon déjà passé)." if abandons.empty?

        apres = reste_du_apres(abandons.pluck(:compte)) do
          AccountEntry.create!(abandons.map { |a| a[:attrs].merge(posted_at: Time.current) })
        end
        corps = abandons.map do |a|
          "  #{a[:compte].code} #{a[:compte].name.ljust(24)} #{euros(a[:du]).rjust(11)}  " \
            "(#{a[:mois].size} mois : #{a[:mois].first(6).join(', ')}#{' …' if a[:mois].size > 6})\n" \
            "      après : #{apres[a[:compte].id]}"
        end
        Plan.new(
          resume: "Abandon #{AccountEntry::FLOW_LABELS[flow]} jusqu'au #{limite} — « #{libelle} »\n#{corps.join("\n")}\n" \
                  "Total abandonné : #{euros(abandons.sum { |a| a[:du] })} sur #{abandons.size} compte(s)",
          empreinte: abandons.map { |a| [a[:compte].id, a[:du]] } + [flow, limite.iso8601, libelle],
          donnees: { abandons: abandons }
        )
      end

      def appliquer(plan)
        abandons = plan.donnees[:abandons]
        AccountEntry.create!(abandons.map { |a| a[:attrs].merge(posted_at: Time.current) })
        "Abandon passé sur #{abandons.size} compte(s), #{euros(abandons.sum { |a| a[:du] })} au total."
      end
    end
  end
end
