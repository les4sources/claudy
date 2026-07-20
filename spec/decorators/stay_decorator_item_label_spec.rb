require "rails_helper"

# Aperçu de fusion (demande Michael 2026-07-20) : un espace réservé N jours
# apparaissait N fois dans la liste — désormais agrégé « Grande Salle (3 j) ».
RSpec.describe StayDecorator, "libellé des lignes d'espaces" do
  let(:customer) { Customer.create!(email: "label@example.com", customer_type: "individual") }
  let(:stay) { Stay.create!(customer: customer, source: "manual", status: "confirmed") }

  it "agrège les espaces par nom avec le nombre de jours" do
    grande = Space.create!(name: "Grande Salle", capacity: 1)
    cuisine = Space.create!(name: "Cuisine professionnelle", capacity: 1)
    from = Date.today + 200
    sb = SpaceBooking.create!(firstname: "Label", group_name: "G",
                              from_date: from, to_date: from + 2, status: "confirmed")
    3.times { |i| SpaceReservation.create!(space: grande, space_booking: sb, date: from + i) }
    SpaceReservation.create!(space: cuisine, space_booking: sb, date: from)
    StayItem.create!(stay: stay, bookable: sb)

    labels = stay.decorate.item_lines.map { |line| line[:name] }

    expect(labels).to include("Grande Salle (3 j), Cuisine professionnelle")
    expect(labels.join).not_to include("Grande Salle, Grande Salle")
  end
end
