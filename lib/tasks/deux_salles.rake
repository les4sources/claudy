namespace :spaces do
  # One-shot idempotente : convertit l'historique de l'espace « Les 2 salles »
  # (décision Michael 2026-07-20). Cet espace disparaît au profit d'une remise
  # DUO automatique au devis (Grande + Petite salle le même jour). On veut donc,
  # côté historique, voir les VRAIS espaces loués : chaque `SpaceReservation`
  # vivante sur « Les 2 salles » devient DEUX `SpaceReservation` (Grande Salle +
  # Petite Salle, MÊME date, MÊME duration) sur le MÊME `SpaceBooking` ; l'originale
  # est DÉTRUITE (hard destroy — ce modèle n'a pas de soft-deletion). Le
  # `price_cents` du SpaceBooking reste STRICTEMENT INCHANGÉ (le prix historique
  # facturé est conservé tel quel) : on assert le total par booking et on rollback
  # ce booking en cas d'écart. En fin d'APPLY, si plus AUCUNE réservation vivante
  # ne pointe l'espace, il est SOFT-DELETÉ.
  #
  # DRY-RUN par défaut (rapport seul, ZÉRO écriture) ; APPLY=1 pour appliquer.
  # Savepoint PAR SpaceBooking (`requires_new: true`) → le DRY-RUN annule réellement
  # ses écritures, même sous fixtures transactionnelles des specs. Idempotente :
  # un re-run après APPLY ne trouve plus de réservation vivante (espace soft-deleté
  # ou vidé) → no-op.
  #
  # Capacité : Grande/Petite ont `capacity 1`. La conversion peut créer un
  # dépassement THÉORIQUE un jour où l'une des salles était déjà réservée
  # séparément → ces collisions sont DÉTECTÉES et listées (`converted_with_conflict`)
  # SANS bloquer (l'historique est l'historique).
  #
  #   bundle exec rake spaces:convert_deux_salles          # DRY-RUN
  #   APPLY=1 bundle exec rake spaces:convert_deux_salles  # RÉEL
  #
  # Résolution des espaces par CODE stable (puis noms candidats) — jamais d'id en
  # dur (cf. SpaceComposition).
  DEUX_SALLES_CODE  = "T+S".freeze
  DEUX_SALLES_NAMES = ["Les 2 salles"].freeze
  GRANDE_CODE  = "TIL".freeze
  GRANDE_NAMES = ["Grande Salle", "Tilleul"].freeze
  PETITE_CODE  = "SAU".freeze
  PETITE_NAMES = ["Petite Salle", "Saule"].freeze

  desc "Convertit l'historique « Les 2 salles » en paires Grande + Petite salle (prix conservé), puis soft-delete l'espace. DRY-RUN sauf APPLY=1"
  task convert_deux_salles: :environment do
    apply = ENV["APPLY"] == "1"

    # Résolution `unscoped` : l'espace « Les 2 salles » peut déjà être soft-deleté
    # (re-run) — on veut quand même le retrouver pour rapporter le no-op idempotent.
    deux   = resolve_space_deux(DEUX_SALLES_CODE, DEUX_SALLES_NAMES)
    grande = resolve_space_deux(GRANDE_CODE, GRANDE_NAMES)
    petite = resolve_space_deux(PETITE_CODE, PETITE_NAMES)

    abort "Espace Grande Salle introuvable (code #{GRANDE_CODE})." if grande.nil?
    abort "Espace Petite Salle introuvable (code #{PETITE_CODE})." if petite.nil?

    if deux.nil?
      puts "=== spaces:convert_deux_salles ==="
      puts "Aucun espace « Les 2 salles » (code #{DEUX_SALLES_CODE}) — rien à convertir (idempotent)."
      next
    end

    report = {
      bookings_scanned: [],           # SpaceBooking touchés
      converted: [],                  # réservations converties (paires OK)
      converted_with_conflict: [],    # paires créées MAIS collision capacité théorique
      failed: [],                     # bookings en erreur (total modifié / exception)
      space_soft_deleted: false
    }

    booking_ids = SpaceBooking.unscoped
                              .joins(:space_reservations)
                              .where(space_reservations: { space_id: deux.id })
                              .distinct
                              .pluck(:id)

    booking_ids.each do |sb_id|
      sb = SpaceBooking.unscoped.find(sb_id)
      report[:bookings_scanned] << sb.id
      originals = sb.space_reservations.where(space_id: deux.id).to_a

      begin
        ActiveRecord::Base.transaction(requires_new: true) do
          before_price = sb.price_cents

          originals.each do |res|
            [grande, petite].each do |target|
              nr = sb.space_reservations.create!(space: target, date: res.date, duration: res.duration)
              if deux_salles_collision?(target: target, date: res.date, exclude_id: nr.id)
                report[:converted_with_conflict] <<
                  "SpaceBooking ##{sb.id} : #{target.name} le #{res.date} déjà réservé séparément (capacité dépassée)"
              end
            end
            res.destroy!
          end

          # Total du SpaceBooking INCHANGÉ (jamais touché ici) — assert + rollback ce
          # booking sinon (garde-fou : on ne reventile pas le prix historique).
          sb.reload
          if sb.price_cents != before_price
            raise "Total modifié (#{before_price} → #{sb.price_cents})"
          end

          raise ActiveRecord::Rollback unless apply
        end

        report[:converted] << "SpaceBooking ##{sb.id} : #{originals.size} rés. → #{originals.size * 2} (Grande + Petite)"
      rescue => e
        report[:failed] << "SpaceBooking ##{sb.id} : #{e.class} #{e.message}"
      end
    end

    # Soft-delete de l'espace SI plus aucune réservation vivante ne le pointe.
    if apply && report[:failed].empty? && SpaceReservation.where(space_id: deux.id).none?
      deux.soft_delete!(validate: false) unless deux.deleted_at.present?
      report[:space_soft_deleted] = true
    end

    print_deux_salles_report(report, apply, deux)
    abort("ÉCHEC : #{report[:failed].size} SpaceBooking en erreur.") if report[:failed].any?
  end
end

# Résolution `unscoped` (inclut soft-deletés) : code stable d'abord, puis noms.
def resolve_space_deux(code, names)
  by_code = Space.unscoped.find_by(code: code)
  return by_code if by_code

  Space.unscoped.where(name: names).min_by { |s| names.index(s.name) || 99 }
end

# Une collision capacité (théorique) existe si une AUTRE réservation vivante
# CONFIRMÉE occupe déjà `target` à `date` (capacity 1) — hors la réservation
# qu'on vient de créer. L'historique n'est pas bloqué, seulement signalé.
def deux_salles_collision?(target:, date:, exclude_id:)
  SpaceReservation
    .joins(:space_booking)
    .where(space_id: target.id, date: date, space_bookings: { status: "confirmed" })
    .where.not(id: exclude_id)
    .exists?
end

def print_deux_salles_report(report, apply, deux)
  puts "=== spaces:convert_deux_salles #{apply ? '(RÉEL)' : '(DRY-RUN)'} ==="
  puts "Espace ciblé                      : ##{deux.id} #{deux.name.inspect} (code #{deux.code.inspect})"
  puts "SpaceBooking touchés              : #{report[:bookings_scanned].size} #{deux_salles_ids(report[:bookings_scanned])}"
  puts "Conversions (paires créées)       : #{report[:converted].size}"
  report[:converted].each { |l| puts "  + #{l}" }
  puts "Collisions capacité (non bloquantes) : #{report[:converted_with_conflict].size}"
  report[:converted_with_conflict].each { |l| puts "  ! #{l}" }
  unless report[:failed].empty?
    puts "Échecs                            : #{report[:failed].size}"
    report[:failed].each { |l| puts "  ✗ #{l}" }
  end
  if apply
    puts(report[:space_soft_deleted] ?
      "Espace « Les 2 salles » SOFT-DELETÉ (plus aucune réservation vivante)." :
      "Espace « Les 2 salles » CONSERVÉ (réservations vivantes restantes ou échecs).")
    puts "OK — conversion appliquée."
  else
    puts "DRY-RUN — aucune écriture. Relancer avec APPLY=1 pour appliquer."
  end
end

def deux_salles_ids(list)
  list.empty? ? "" : "→ #{list.sort.join(', ')}"
end
