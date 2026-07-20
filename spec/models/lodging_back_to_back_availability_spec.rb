require "rails_helper"

# Issue #94 — sur-blocage au jour de rotation.
# Les `Reservation` d'occupation couvrent les NUITS `[arrivée, départ)` : le jour
# de départ n'est PAS occupé. Les requêtes de disponibilité doivent donc interroger
# les nuits `from..(départ-1)` et non `from..départ` inclusif — sinon une rotation
# dos-à-dos (départ le jour J / arrivée d'un autre séjour le même jour J) est
# faussement refusée. Le garde-fou : l'appel nuit-unique `available_on?(d)` (=
# `available_between?(d, d)`) doit rester exact (anti-surbooking).
RSpec.describe Lodging, "disponibilité dos-à-dos (issue #94)", type: :model do
  let!(:hulotte) do
    lodging = Lodging.create!(name: "La Hulotte", price_night_cents: 48_500)
    lodging.rooms << room
    lodging
  end
  let(:room) { Room.create!(name: "Chambre 1", level: 1) }

  # Jours de référence.
  let(:d1) { Date.new(2026, 8, 1) }
  let(:d2) { Date.new(2026, 8, 2) }
  let(:d3) { Date.new(2026, 8, 3) }
  let(:d4) { Date.new(2026, 8, 4) }
  let(:d5) { Date.new(2026, 8, 5) }

  # Occupe (confirmé) une chambre sur les NUITS `[from, to)` — le jour `to`
  # (départ) n'est jamais réservé, comme en production.
  def occupy(target_room, from:, to:)
    booking = Booking.create!(firstname: "Occ", from_date: from, to_date: to, adults: 1, status: "confirmed", lodging: hulotte)
    (from...to).each { |date| Reservation.create!(booking: booking, room: target_room, date: date) }
    booking
  end

  describe "gîte entier (#available_between?)" do
    it "reste disponible pour un séjour APRÈS un séjour dos-à-dos (A[1→3] puis B[3→5])" do
      occupy(room, from: d1, to: d3) # nuits 1, 2
      expect(hulotte.available_between?(d3, d5)).to be(true)
    end

    it "reste disponible pour un séjour AVANT un séjour dos-à-dos (B[3→5] puis A[1→3])" do
      # Cas discriminant : avant le fix, la requête `date: 1..3` INCLUSIVE captait
      # la nuit d'arrivée (jour 3) de B et refusait A à tort.
      occupy(room, from: d3, to: d5) # nuits 3, 4
      expect(hulotte.available_between?(d1, d3)).to be(true)
    end

    it "refuse un vrai chevauchement (A[1→3] vs [2→4], nuit 2 commune)" do
      occupy(room, from: d1, to: d3) # nuits 1, 2
      expect(hulotte.available_between?(d2, d4)).to be(false)
    end

    it "refuse une fenêtre partageant une seule nuit (A[1→3] vs [2→3], nuit 2 commune)" do
      occupy(room, from: d1, to: d3) # nuits 1, 2
      expect(hulotte.available_between?(d2, d3)).to be(false)
    end
  end

  describe "chambres seules (#rooms_available_between?)" do
    it "reste disponible pour un séjour APRÈS un séjour dos-à-dos sur la même chambre" do
      occupy(room, from: d1, to: d3)
      expect(hulotte.rooms_available_between?([room.id], d3, d5)).to be(true)
    end

    it "reste disponible pour un séjour AVANT un séjour dos-à-dos sur la même chambre" do
      occupy(room, from: d3, to: d5)
      expect(hulotte.rooms_available_between?([room.id], d1, d3)).to be(true)
    end

    it "refuse un vrai chevauchement sur la même chambre (nuit 2 commune)" do
      occupy(room, from: d1, to: d3)
      expect(hulotte.rooms_available_between?([room.id], d2, d4)).to be(false)
      expect(hulotte.rooms_available_between?([room.id], d2, d3)).to be(false)
    end
  end

  describe "nuit unique préservée (garde-fou anti-surbooking, #available_on?)" do
    before { occupy(room, from: d2, to: d3) } # occupe UNIQUEMENT la nuit 2

    it "est indisponible sur la nuit couverte par une Reservation confirmée" do
      expect(hulotte.available_on?(d2)).to be(false)
    end

    it "reste disponible sur une nuit libre — AUCUN sur-blocage" do
      expect(hulotte.available_on?(d1)).to be(true) # veille libre
      expect(hulotte.available_on?(d3)).to be(true) # jour de départ, non occupé
      expect(hulotte.available_on?(d5)).to be(true) # nuit sans lien
    end
  end

  describe "Unavailability (indispo manuelle — sémantique JOURNÉE PLEINE conservée)" do
    it "bloque une fenêtre dont le JOUR DE DÉPART porte une indisponibilité" do
      # Contrairement aux Reservation nuitées, l'indispo posée à la main couvre la
      # journée pleine `from..to` INCLUSIF : une indispo sur le jour de départ bloque.
      Unavailability.create!(lodging: hulotte, date: d3)
      expect(hulotte.available_between?(d1, d3)).to be(false)
      expect(hulotte.rooms_available_between?([room.id], d1, d3)).to be(false)
    end
  end
end
