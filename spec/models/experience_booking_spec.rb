# == Schema Information
#
# Table name: experience_bookings
#
#  id                          :bigint           not null, primary key
#  experience_availability_id  :bigint           not null
#  stay_id                     :bigint           not null
#  participants                :integer
#  status                      :string           default("pending")
#  notes                       :text
#  refusal_reason              :text
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#
require "rails_helper"

# Epic #55 — Phase 2 : validation/refus des activités par les porteurs.
RSpec.describe ExperienceBooking, type: :model do
  let(:customer)   { Customer.create!(email: "eb@example.com", customer_type: "individual") }
  let(:stay)       { Stay.create!(customer: customer) }
  let(:porteur)    { Human.create!(name: "Porteuse Balade", email: "porteuse@example.com") }
  let(:experience) { Experience.create!(name: "Balade avec les ânes", human: porteur, fixed_price_cents: 3_000) }
  let(:availability) do
    ExperienceAvailability.create!(experience: experience, available_on: Date.today + 20, starts_at: "10:00")
  end

  def booking(status: "pending", reason: nil)
    ExperienceBooking.create!(
      experience_availability: availability, stay: stay, participants: 2,
      status: status, refusal_reason: reason
    )
  end

  describe "statut refused + raison obligatoire" do
    it "accepte refused avec une raison" do
      eb = booking
      expect(eb.refuse!("Créneau déjà complet")).to be_truthy
      expect(eb.reload).to be_refused
      expect(eb.refusal_reason).to eq("Créneau déjà complet")
    end

    it "refuse un refused sans raison" do
      eb = booking
      expect { eb.refuse!("") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(eb.reload).to be_pending
    end

    it "n'exige pas de raison pour les autres statuts" do
      expect(booking(status: "confirmed")).to be_valid
      expect(booking(status: "cancelled")).to be_valid
      expect(booking(status: "pending")).to be_valid
    end
  end

  describe "transitions" do
    it "pending → confirmed via #confirm!" do
      eb = booking
      eb.confirm!
      expect(eb.reload).to be_confirmed
    end

    it "pending → refused via #refuse!(reason)" do
      eb = booking
      eb.refuse!("Indisponible ce jour-là")
      expect(eb.reload).to be_refused
    end
  end

  describe "scope .active" do
    it "exclut les activités annulées ET refusées" do
      keep    = booking(status: "confirmed")
      booking(status: "cancelled")
      booking(status: "refused", reason: "non")

      expect(ExperienceBooking.active).to contain_exactly(keep)
    end
  end

  describe "scoping porteur" do
    let(:autre_porteur)   { Human.create!(name: "Autre Porteur", email: "autre@example.com") }
    let(:autre_experience){ Experience.create!(name: "Poterie", human: autre_porteur) }
    let(:autre_avail) do
      ExperienceAvailability.create!(experience: autre_experience, available_on: Date.today + 21, starts_at: "14:00")
    end

    it ".for_carrier ne renvoie que les réservations des activités du porteur" do
      mine   = booking
      theirs = ExperienceBooking.create!(experience_availability: autre_avail, stay: stay, participants: 1)

      expect(ExperienceBooking.for_carrier(porteur)).to include(mine)
      expect(ExperienceBooking.for_carrier(porteur)).not_to include(theirs)
    end

    it ".for_user renvoie tout pour un admin global, ses activités pour un porteur" do
      mine   = booking
      theirs = ExperienceBooking.create!(experience_availability: autre_avail, stay: stay, participants: 1)

      admin_user   = User.create!(email: "staff@les4sources.be", password: "password123")
      porteur_user = User.create!(email: "porteuse@example.com", password: "password123", human: porteur)

      expect(ExperienceBooking.for_user(admin_user)).to include(mine, theirs)
      expect(ExperienceBooking.for_user(porteur_user)).to contain_exactly(mine)
    end
  end

  describe "jeton de validation" do
    it "résout le bon enregistrement" do
      eb = booking
      expect(ExperienceBooking.find_by_validation_token(eb.validation_token)).to eq(eb)
    end

    it "ne vaut que pour cette portée (purpose)" do
      eb = booking
      forged = eb.signed_id(purpose: :autre_chose)
      expect(ExperienceBooking.find_by_validation_token(forged)).to be_nil
    end

    it "renvoie nil pour un jeton bidon" do
      expect(ExperienceBooking.find_by_validation_token("n-importe-quoi")).to be_nil
    end
  end
end
