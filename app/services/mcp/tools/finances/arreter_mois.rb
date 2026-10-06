module Mcp
  module Tools
    module Finances
      # Comptabilité > Arrêté du mois (MonthlyCloseController#close et
      # #reopen) : arrêter un mois quand plus rien ne bloque, ou le rouvrir.
      # Un mois arrêté ne reçoit plus de ligne de caisse ni de correction.
      class ArreterMois < Ecriture
        include Commun

        tool "arreter_mois",
             title: "Arrêter ou rouvrir un mois",
             description: "Arrête un mois comptable (refusé tant qu'un point bloquant de arrete_du_mois reste ouvert) " \
                          "ou le rouvre (motif obligatoire). Un mois arrêté ne se modifie plus : feuille de caisse, " \
                          "paiements en espèces, corrections.",
             schema: {
               properties: {
                 mois: MOIS.merge(description: "Mois, AAAA-MM. Défaut : le mois précédent."),
                 geste: { type: "string", enum: %w[arreter rouvrir], description: "arreter (défaut) ou rouvrir." },
                 notes: { type: "string", description: "Pour arreter : une note gardée avec l'arrêté." }
               }
             }

        private

        def planifier(arguments)
          mois = mois!(arguments["mois"], defaut: Date.current.prev_month.beginning_of_month)
          geste = arguments["geste"].presence || "arreter"
          raise Error, "geste : arreter ou rouvrir." unless %w[arreter rouvrir].include?(geste)

          cloture = MonthClosing.find_by(period_month: mois)
          if geste == "rouvrir"
            raise Error, "#{nom_mois(mois).capitalize} n'est pas arrêté." if cloture.nil?

            motif!({ "motif" => @motif })
            return Plan.new(resume: "ROUVRIR #{nom_mois(mois)} (arrêté le #{I18n.l(cloture.closed_at.to_date)} par #{cloture.closed_by || '—'}).",
                            empreinte: [etat_de(cloture), geste], donnees: { mois: mois.iso8601, geste: geste })
          end

          raise Error, "#{nom_mois(mois).capitalize} est déjà arrêté." if cloture
          raise Error, "On n'arrête pas un mois qui n'est pas fini." if mois.end_of_month >= Date.current

          bloquantes = ::Finance::MonthlyClose.call(month: mois).select(&:blocking?).reject { |e| e.key == :closing }
          if bloquantes.any?
            raise Error, "Il reste #{bloquantes.size} point(s) à traiter : " +
                         bloquantes.map { |e| "#{e.title} (#{e.detail})" }.join(" · ")
          end

          Plan.new(resume: "ARRÊTER #{nom_mois(mois)}#{" — note : #{arguments['notes']}" if arguments['notes'].present?}. " \
                           "Plus aucune saisie ni correction sur ce mois ensuite.",
                   empreinte: [mois.iso8601, geste, arguments["notes"].to_s], donnees: { mois: mois.iso8601, geste: geste, notes: arguments["notes"].to_s.strip.presence })
        end

        def appliquer(plan)
          mois = Date.iso8601(plan.donnees[:mois])
          if plan.donnees[:geste] == "rouvrir"
            MonthClosing.find_by(period_month: mois)&.destroy!
            return "#{nom_mois(mois).capitalize} est rouvert."
          end

          metier! { MonthClosing.create!(period_month: mois, closed_at: Time.current, closed_by: whodunnit, notes: plan.donnees[:notes]) }
          "#{nom_mois(mois).capitalize} est arrêté."
        end
      end
    end
  end
end
