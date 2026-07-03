# == Schema Information
#
# Table name: spaces
#
#  id          :bigint           not null, primary key
#  name        :string
#  description :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  code        :string
#  deleted_at  :datetime
#  position    :integer          default(999)
#  capacity    :integer          default(1), not null
#
require 'rails_helper'

RSpec.describe Space, type: :model do
  let(:date) { Date.new(2030, 8, 1) }

  # Confirme un groupe de plus sur l'espace au jour donné.
  def book(space, on: date)
    booking = SpaceBooking.create!(firstname: "G", from_date: on, to_date: on, status: "confirmed")
    SpaceReservation.create!(space: space, space_booking: booking, date: on)
  end

  describe "validations" do
    it "exige un nom" do
      space = Space.new(name: nil, capacity: 1)
      expect(space).not_to be_valid
      expect(space.errors[:name]).to be_present
    end

    it "refuse une capacité nulle" do
      space = Space.new(name: "Sans capacité", capacity: nil)
      expect(space).not_to be_valid
      expect(space.errors[:capacity]).to be_present
    end

    it "refuse une capacité inférieure à 1" do
      space = Space.new(name: "Zéro", capacity: 0)
      expect(space).not_to be_valid
      expect(space.errors[:capacity]).to be_present
    end

    it "accepte une capacité entière ≥ 1" do
      expect(Space.new(name: "Salle", capacity: 1)).to be_valid
      expect(Space.new(name: "Bois", capacity: 5)).to be_valid
    end
  end

  describe "capacity" do
    it "defaults to 1 (espace exclusif — comportement historique)" do
      expect(Space.new.capacity).to eq(1)
    end

    context "espace exclusif (capacity 1, ex. une salle)" do
      let(:salle) { Space.create!(name: "Grande Salle", capacity: 1) }

      it "est bloqué dès le premier groupe confirmé" do
        expect(salle.available_on?(date)).to be(true)
        book(salle)
        expect(salle.available_on?(date)).to be(false)
        expect(salle).to be_booked_on(date)
      end

      it "n'est pas considéré comme partagé" do
        expect(salle.shared?).to be(false)
      end
    end

    context "espace multi-groupe (capacity 3, ex. Bois/Pâture)" do
      let(:bois) { Space.create!(name: "Bois", capacity: 3) }

      it "accepte plusieurs groupes jusqu'à la capacité" do
        expect(bois.remaining_capacity_on(date)).to eq(3)
        book(bois)
        expect(bois.available_on?(date)).to be(true)
        expect(bois.remaining_capacity_on(date)).to eq(2)
        book(bois)
        expect(bois.available_on?(date)).to be(true)
      end

      it "bloque une fois la capacité atteinte" do
        3.times { book(bois) }
        expect(bois.available_on?(date)).to be(false)
        expect(bois.remaining_capacity_on(date)).to eq(0)
      end

      it "est considéré comme partagé" do
        expect(bois.shared?).to be(true)
      end
    end

    it "ignore les réservations non confirmées et les autres jours" do
      bois = Space.create!(name: "Bois", capacity: 1)
      pending_booking = SpaceBooking.create!(firstname: "P", from_date: date, to_date: date, status: "pending")
      SpaceReservation.create!(space: bois, space_booking: pending_booking, date: date)
      SpaceReservation.create!(
        space: bois,
        space_booking: SpaceBooking.create!(firstname: "C", from_date: date - 1, to_date: date - 1, status: "confirmed"),
        date: date - 1
      )
      expect(bois.available_on?(date)).to be(true)
    end
  end
end
