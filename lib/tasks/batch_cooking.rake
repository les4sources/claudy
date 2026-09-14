namespace :batch_cooking do
  desc "Rejoue les écritures de toutes les sessions de batch cooking (issue #307 — rattrapage après le passage aux personnes × repas)"
  task replay_entries: :environment do
    # Le rejeu est le SEUL chemin qui corrige les écritures d'une session déjà
    # encodée : la migration ne touche pas la comptabilité, et le formulaire ne
    # se rouvre pas tout seul. On la lance à la main après déploiement.
    #
    # Chronologique, parce qu'une session refusée ne doit pas empêcher les
    # suivantes : on la compte, on dit pourquoi, et on continue. Une écriture
    # verrouillée par un décompte émis est un refus LÉGITIME — le rapport le
    # dit, quelqu'un tranche ensuite par contre-écriture.
    corrigees = []
    inchangees = 0
    refusees = []

    BatchCookingSession.chronological.each do |session|
      rapport = Finance::RecordBatchCooking.new(session: session,
                                                whodunnit: "rake batch_cooking:replay_entries").run!

      if rapport.touched.zero?
        inchangees += 1
      else
        corrigees << [ session, rapport ]
      end
    rescue ServiceError => e
      refusees << [ session, e.message ]
    end

    puts "[batch_cooking:replay_entries] #{corrigees.size} session(s) corrigée(s), " \
         "#{inchangees} inchangée(s), #{refusees.size} refusée(s)."

    corrigees.each do |session, rapport|
      puts "  ✅ #{session.title} — #{rapport.summary} (#{session.meals_count} repas × " \
           "#{session.people_served} personnes = #{session.portions_served} portions)"
    end

    refusees.each do |session, message|
      puts "  ⛔ #{session.title} — #{message}"
    end
  end
end
