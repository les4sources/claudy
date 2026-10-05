module Mcp
  module Tools
    # Ce que `diagnostic.rb` faisait en console : ce que Claudy réclame poste
    # par poste, et les lignes encore ouvertes derrière chaque montant.
    class DiagnosticCompte < Base
      tool "diagnostic_compte",
           title: "Diagnostic d'un compte",
           description: "Ce que Claudy réclame à un compte, poste par poste, avec les lignes encore dues derrière " \
                        "chaque montant (après imputation des règlements), les avances et les charges récurrentes. " \
                        "Le point de départ de toute question sur un compte contesté.",
           schema: {
             properties: {
               compte: COMPTE,
               lignes_par_poste: { type: "integer", description: "Lignes ouvertes montrées par poste (20 par défaut)." }
             },
             required: ["compte"]
           }

      def call(arguments)
        compte = compte!(arguments["compte"])
        limite = (arguments["lignes_par_poste"] || 20).to_i.clamp(1, 500)
        dus = MemberAccounts::Outstanding.new(compte)

        sortie = ["Compte #{compte.code} — #{compte.name} (#{compte.kind_label}#{', inactif' unless compte.active})",
                  "Solde global #{euros(compte.balance_cents)} · reste dû #{euros(dus.total_cents)} · " \
                  "ouverture #{euros(compte.opening_balance_cents)} au #{compte.opening_balance_on || '—'}"]

        sortie << "\nCe que Claudy réclame, poste par poste :"
        sortie << "  (rien)" if dus.postes.empty?
        dus.postes.each do |poste|
          sortie << "  #{poste.label} : #{euros(poste.amount_cents)} (plus ancien : #{poste.oldest_on})"
          poste.lignes.last(limite).each do |ligne|
            mois = ligne.mois_vise ? " [vise #{ligne.mois_vise.strftime('%Y-%m')}]" : ""
            sortie << "    #{ligne.entry_date}  #{euros(ligne.amount_cents).rjust(11)}  #{ligne.label}#{mois}"
          end
          sortie << "    … #{poste.lignes.size - limite} ligne(s) plus anciennes" if poste.lignes.size > limite
        end

        if dus.avances.any?
          sortie << "\nAvances (payé au-delà de ce que le poste réclamait) :"
          dus.avances.each { |flow, cents| sortie << "  #{AccountEntry::FLOW_LABELS.fetch(flow, flow)} #{euros(cents)}" }
        end

        charges = RecurringCharge.where(member_account: compte).order(:starts_on)
        if charges.any?
          sortie << "\nCharges récurrentes :"
          charges.each do |charge|
            montant = charge.amount_cents ? euros(charge.amount_cents) : "tarif #{charge.rate_key}"
            sortie << "  ##{charge.id} « #{charge.label} » #{montant} · poste #{charge.flow || '—'} · " \
                      "#{charge.active ? 'active' : 'inactive'} du #{charge.starts_on} au #{charge.ends_on || '—'}"
          end
        end

        sortie.join("\n")
      end
    end
  end
end
