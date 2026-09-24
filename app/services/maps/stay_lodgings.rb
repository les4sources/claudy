# Les gîtes d'un séjour sur la carte (epic #348, phase 4) : ce que la page
# publique `/sejour/:token/carte` surligne et sur quoi elle se centre.
#
# Un gîte se retrouve de deux façons : le gîte réservé (`Booking.lodging_id`),
# ou les chambres réservées (`Reservation` → `LodgingRoom`) pour une réservation
# à la chambre. Un gîte COMPOSITE (le Grand-Duc) n'a pas de tracé — ses
# composantes en ont un (cf. `Maps::Venues`) : on descend donc vers elles.
#
# Ne sert qu'à dire OÙ dorment les hôtes de CE séjour : aucune date, aucun
# autre séjour n'en sort.
module Maps
  class StayLodgings
    def initialize(stay)
      @stay = stay
    end

    def lodging_ids
      @lodging_ids ||= begin
        booking_ids = @stay.stay_items.where(bookable_type: "Booking").pluck(:bookable_id)
        booked = Booking.where(id: booking_ids).where.not(lodging_id: nil).pluck(:lodging_id)
        room_ids = Reservation.where(booking_id: booking_ids).distinct.pluck(:room_id)
        via_rooms = LodgingRoom.where(room_id: room_ids).distinct.pluck(:lodging_id)
        ids = (booked + via_rooms).uniq
        (ids + LodgingComposition.where(composite_lodging_id: ids).pluck(:component_lodging_id)).uniq
      end
    end

    # Les tracés de ces gîtes dans la couche des lieux (phase 3).
    def features
      return MapFeature.none if lodging_ids.empty?

      MapFeature.where(map_layer: MapLayer.where(kind: "venues"), linked_type: "Lodging", linked_id: lodging_ids)
                .includes(:linked).ordered
    end

    # Ce qu'un hôte voit de son gîte : le tracé et le nom du gîte. Rien d'autre.
    def as_geojson
      {
        type: "FeatureCollection",
        features: features.map do |feature|
          { type: "Feature", geometry: feature.geometry, properties: { name: feature.linked&.name || feature.name(:fr) } }
        end
      }
    end
  end
end
