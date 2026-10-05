module Mcp
  module Tools
    # `bar-par-mois.rb`, pour n'importe quel poste : facturé et réglé mois par
    # mois, et l'écart cumulé. Un règlement qui nomme son mois
    # (« reprise-bar:2026-05 ») est rangé dans CE mois ; les autres, dans le
    # mois où ils ont été reçus, marqués comme tels.
    class PosteParMois < Base
      tool "poste_par_mois",
           title: "Poste mois par mois",
           description: "Pour un compte et un poste : facturé, réglé, écart et cumul mois par mois. Montre d'un coup " \
                        "d'œil quel mois n'a pas été payé.",
           schema: {
             properties: { compte: COMPTE, poste: POSTE, du: DATE.merge(description: "Premier mois (AAAA-MM-JJ, facultatif).") },
             required: %w[compte poste]
           }

      def call(arguments)
        compte = compte!(arguments["compte"])
        flow = poste!(arguments["poste"])
        lignes = compte.account_entries.where(flow: flow).includes(:account_settlement).to_a
        return "Aucune ligne #{AccountEntry::FLOW_LABELS[flow]} sur #{compte.code}." if lignes.empty?

        facture = Hash.new(0)
        regle = Hash.new(0)
        lignes.each do |entry|
          if entry.amount_cents.positive?
            facture[entry.entry_date.strftime("%Y-%m")] += entry.amount_cents
          else
            regle[mois_regle(entry)] += -entry.amount_cents
          end
        end

        debut = date_ou_nil(arguments["du"], "du")&.strftime("%Y-%m")
        cumul = 0
        corps = (facture.keys | regle.keys).sort_by { |mois| mois.delete("(") }.filter_map do |mois|
          ecart = facture[mois] - regle[mois]
          cumul += ecart
          next if debut && mois.delete("(") < debut

          "#{mois.ljust(22)} facturé #{euros(facture[mois]).rjust(11)}  réglé #{euros(regle[mois]).rjust(11)}  " \
            "écart #{euros(ecart).rjust(11)}  cumul #{euros(cumul).rjust(11)}"
        end

        "#{compte.code} — #{compte.name} · #{AccountEntry::FLOW_LABELS[flow]} mois par mois\n#{corps.join("\n")}\n" \
          "« (AAAA-MM reçu) » = règlement sans mois nommé, rangé au mois de sa réception."
      end

      private

      def mois_regle(entry)
        annee, mois = entry.account_settlement&.reference.to_s.match(MemberAccounts::Outstanding::MOIS_VISE)&.captures
        annee ? "#{annee}-#{mois}" : "(#{entry.entry_date.strftime('%Y-%m')} reçu)"
      end
    end
  end
end
