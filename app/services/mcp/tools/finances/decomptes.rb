module Mcp
  module Tools
    module Finances
      # Finances > Décomptes (StatementsController#index) : les décomptes
      # mensuels des comptes courants, émis ou à émettre.
      class Decomptes < Base
        include Commun

        tool "decomptes",
             title: "Décomptes mensuels",
             description: "Les décomptes d'un mois : ceux qui sont émis (statut, solde de clôture, envoi, relances) et " \
                          "les comptes actifs qui n'en ont pas encore (au solde non nul, sauf `avec_soldes_nuls`). " \
                          "Défaut : le mois en cours. Pour émettre, envoyer, relancer ou marquer réglé : decompte.",
             schema: {
               properties: {
                 mois: MOIS,
                 avec_soldes_nuls: { type: "boolean", description: "Lister aussi les comptes à 0 € parmi ceux à émettre." }
               }
             }

        def call(arguments)
          mois = mois!(arguments["mois"], defaut: Date.current.beginning_of_month)
          emis = AccountStatement.for_month(mois).includes(member_account: :human).to_a.sort_by { |s| s.member_account.name.to_s }
          deja = emis.map(&:member_account_id)
          candidats = MemberAccount.ordered.where(active: true).where.not(id: deja).to_a
          candidats = candidats.reject { |c| c.balance_cents.zero? } unless arguments["avec_soldes_nuls"]

          lignes_emis = emis.map do |s|
            compte = s.member_account
            sans_email = compte.contact_email.blank? && compte.human&.email.blank?
            "Décompte ##{s.id} #{compte.code} #{compte.name} · #{s.status_label} · solde #{euros(s.closing_balance_cents)}" \
              "#{" · envoyé le #{I18n.l(s.sent_at.to_date)}" if s.sent_at}#{" · #{s.reminders_count} relance(s)" if s.reminders_count.to_i.positive?}" \
              "#{" · PAS D'EMAIL DE CONTACT" if sans_email}"
          end
          lignes_candidats = candidats.map { |c| "#{c.code} #{c.name} · solde #{euros(c.balance_cents)}" }

          [
            "Décomptes de #{nom_mois(mois)} : #{emis.size} émis.",
            lignes_emis.join("\n").presence,
            "À émettre (#{candidats.size}) :\n#{lignes_candidats.presence&.join("\n") || 'aucun'}"
          ].compact.join("\n\n")
        end
      end
    end
  end
end
