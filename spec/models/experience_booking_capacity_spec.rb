require "rails_helper"

# Décision Michael 2026-08-21 : la capacité d'un créneau devient une vraie
# barrière côté client, pas seulement un filtre d'affichage. Le funnel masquait
# les créneaux pleins, mais rien n'empêchait deux clients simultanés — ni un
# POST direct — de dépasser `max_participants`. L'équipe, elle, garde la main.
RSpec.describe ExperienceBooking, "capacité d'un créneau" do
  let(:customer)   { Customer.create!(email: "cap@example.com", customer_type: "individual") }
  let(:stay)       { Stay.create!(customer: customer, arrival_date: Date.today + 10, departure_date: Date.today + 12) }
  let(:experience) { Experience.create!(name: "Poterie", price_cents: 2_000) }
  let(:slot)       { ExperienceAvailability.create!(experience: experience, available_on: Date.today + 11, starts_at: "10:00", max_participants: 4) }

  def book(participants, status: "pending", override: false)
    booking = ExperienceBooking.new(experience_availability: slot, stay: stay,
                                    participants: participants, status: status)
    booking.refusal_reason = "motif" if status == "refused"
    booking.capacity_override = override
    booking
  end

  it "accepte une réservation qui tient dans le créneau" do
    expect(book(4)).to be_valid
  end

  it "refuse ce qui dépasse la capacité" do
    booking = book(5)

    expect(booking).not_to be_valid
    expect(booking.errors[:participants].join).to include("il ne reste que 4")
  end

  it "compte les réservations déjà posées" do
    book(3).save!

    expect(book(2)).not_to be_valid
    expect(book(1)).to be_valid
  end

  it "laisse passer l'équipe quand elle force" do
    book(4).save!

    expect(book(3, override: true)).to be_valid
  end

  it "ne borne rien quand le créneau n'a pas de capacité déclarée" do
    libre = ExperienceAvailability.create!(experience: experience, available_on: Date.today + 11, starts_at: "14:00")
    booking = ExperienceBooking.new(experience_availability: libre, stay: stay, participants: 99)

    expect(booking).to be_valid
  end

  # Le scope `active` écarte déjà les refusées ; `booked_participants` ne le
  # faisait pas. Un refus rendait le créneau artificiellement plus plein.
  it "libère les places d'une activité refusée ou annulée" do
    book(4, status: "refused").save!
    expect(slot.reload.booked_participants).to eq(0)

    book(4, status: "cancelled").save!
    expect(slot.reload.booked_participants).to eq(0)
    expect(book(4)).to be_valid
  end

  it "ne se compte pas elle-même quand on édite ses participants" do
    booking = book(4)
    booking.save!

    booking.participants = 3
    expect(booking).to be_valid

    booking.participants = 5
    expect(booking).not_to be_valid
  end

  # Michael 2026-10-01 (CLAUDY-7Z) : une activité posée par l'équipe au-delà de
  # la capacité répondait 422 à la validation, qui ne prend pourtant aucune place.
  context "réservation déjà posée au-delà de la capacité" do
    # Rechargée comme en production : `capacity_override` ne vit que sur
    # l'instance qui a créé la réservation.
    let(:booking) { ExperienceBooking.find(book(43, override: true).tap(&:save!).id) }

    it "se valide" do
      expect { booking.confirm! }.not_to raise_error
      expect(booking.reload).to be_confirmed
    end

    it "se déclare tenue une fois le créneau passé" do
      booking.confirm!
      slot.update_column(:available_on, Date.today - 3)
      expect { booking.reload.mark_held! }.not_to raise_error
    end

    it "se réenregistre à l'identique et peut baisser" do
      expect(booking.update(participants: 43)).to be(true)
      expect(booking.update(participants: 40)).to be(true)
    end

    it "refuse encore une hausse" do
      expect(booking.update(participants: 44)).to be(false)
    end

    it "est recontrôlée quand une annulée revit" do
      booking.update!(status: "cancelled")
      booking.reload
      expect(booking.update(status: "pending")).to be(false)
    end
  end
end
