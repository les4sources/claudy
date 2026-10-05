module Mcp
  module Tools
    class ChercherComptes < Base
      tool "chercher_comptes",
           title: "Chercher des comptes",
           description: "Liste les comptes courants (familles, personnes, entités) avec leur code, leur solde " \
                        "et ce qu'ils doivent encore poste par poste. Sans recherche : tous les comptes actifs.",
           schema: {
             properties: {
               recherche: { type: "string", description: "Partie du nom ou du code (facultatif)." },
               inclure_inactifs: { type: "boolean", description: "Inclure les comptes désactivés. Non par défaut." }
             }
           }

      LIMITE = 100

      def call(arguments)
        scope = MemberAccount.ordered
        scope = scope.actives unless arguments["inclure_inactifs"]
        if arguments["recherche"].present?
          motif = "%#{MemberAccount.sanitize_sql_like(arguments['recherche'].to_s.strip)}%"
          scope = scope.where("name ILIKE :m OR code ILIKE :m", m: motif)
        end

        comptes = MemberAccounts::Summary.new(scope.limit(LIMITE)).accounts.sort_by(&:code)
        return "Aucun compte trouvé." if comptes.empty?

        nets = MemberAccounts::Outstanding.nets_par_poste(comptes)
        lignes = comptes.map do |compte|
          dus = nets[compte.id].select { |_, cents| cents.positive? }
          detail = dus.map { |flow, cents| "#{AccountEntry::FLOW_LABELS.fetch(flow, flow)} #{euros(cents)}" }.join(", ")
          "#{compte.code} · #{compte.name} (#{compte.kind_label}#{', inactif' unless compte.active}) · " \
            "solde #{euros(compte.balance_cents)} · dû #{euros(MemberAccounts::Outstanding.du(nets[compte.id]))}" \
            "#{" (#{detail})" if detail.present?}"
        end
        "#{comptes.size} compte(s)#{" (limité à #{LIMITE})" if comptes.size == LIMITE} :\n#{lignes.join("\n")}"
      end
    end
  end
end
