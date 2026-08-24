namespace :space_reservations do
  desc "Supprime les SpaceReservation en doublon (même réservation, même espace, même date) — Michael 2026-08-25"
  task dedupe: :environment do
    apply = ENV["APPLY"] == "1"

    # Un (space_booking, space, date) ne décrit qu'UNE occupation : la salle est
    # prise ce jour-là, et sa durée dit journée / soirée / les deux. Les lignes
    # jumelles doublaient les badges du calendrier ET l'occupation comptée par
    # `Space#available_on?` — une salle réservée une fois pouvait s'y compter deux
    # et bloquer une disponibilité réelle.
    groupes = SpaceReservation.group(:space_booking_id, :space_id, :date)
                              .having("count(*) > 1").count

    a_supprimer = []
    durees_divergentes = []

    groupes.each_key do |space_booking_id, space_id, date|
      lignes = SpaceReservation.where(space_booking_id: space_booking_id, space_id: space_id, date: date)
                               .order(:id).to_a
      # On garde la PLUS ANCIENNE (plus petit id) : c'est la ligne d'origine, celle
      # que porte l'historique PaperTrail de la réservation.
      gardee, *surnumeraires = lignes

      # Garde-fou : deux lignes de durées DIFFÉRENTES ne sont pas un doublon franc
      # (« journée » + « soirée » décrivent deux moments). On ne les touche pas et
      # on les signale — à traiter à la main plutôt qu'à écraser en silence.
      if lignes.map(&:duration).compact_blank.uniq.size > 1
        durees_divergentes << [gardee.id, lignes.map { |l| "#{l.id}:#{l.duration}" }.join(" ")]
        next
      end

      a_supprimer.concat(surnumeraires.map(&:id))
    end

    puts "Groupes en doublon        : #{groupes.size}"
    puts "Lignes surnuméraires      : #{a_supprimer.size}"
    puts "Réservations concernées   : #{groupes.keys.map(&:first).uniq.size}"
    if durees_divergentes.any?
      puts "⚠️  Durées divergentes (NON touchées, à trancher à la main) :"
      durees_divergentes.each { |gardee, detail| puts "    autour de sr##{gardee} → #{detail}" }
    end
    puts "Ids à supprimer           : #{a_supprimer.first(50).join(', ')}#{a_supprimer.size > 50 ? '…' : ''}" if a_supprimer.any?

    if apply && a_supprimer.any?
      SpaceReservation.where(id: a_supprimer).destroy_all
      puts "APPLIQUÉ — #{a_supprimer.size} ligne(s) supprimée(s)."
    else
      puts apply ? "APPLIQUÉ — rien à supprimer." : "DRY-RUN — relancer avec APPLY=1 pour supprimer."
    end
  end
end
