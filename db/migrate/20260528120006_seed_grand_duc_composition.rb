class SeedGrandDucComposition < ActiveRecord::Migration[7.0]
  # Wires the Grand-Duc = Hulotte + Chevêche composition on existing data
  # (idempotent). Availability of Grand-Duc is then derived on the fly from its
  # components, with no stored blocking (decision §11.4 / AC-23/24/25/51).
  def up
    grand_duc = Lodging.unscoped.find_by(name: "Le Grand-Duc")
    hulotte   = Lodging.unscoped.find_by(name: "La Hulotte")
    cheveche  = Lodging.unscoped.find_by(name: "La Chevêche")

    return unless grand_duc && hulotte && cheveche

    [hulotte, cheveche].each do |component|
      LodgingComposition.find_or_create_by!(
        composite_lodging_id: grand_duc.id,
        component_lodging_id: component.id
      )
    end
  end

  def down
    grand_duc = Lodging.unscoped.find_by(name: "Le Grand-Duc")
    return unless grand_duc

    LodgingComposition.where(composite_lodging_id: grand_duc.id).delete_all
  end
end
