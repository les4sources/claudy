require "rails_helper"

# Epic #144, phase 6 — specs de CAPTURE du comportement fuseau horaire.
#
# Rails 8.0 change `to_time_preserves_timezone` (true → :zone). Claudy a des
# appels `to_time` sur le chemin métier des réservations et des formulaires :
#   - Reservation#start_time / SpaceReservation#start_time : `date.to_time`
#     (minuit — mais dans QUEL fuseau ? celui du système, pas celui de l'app)
#   - events/gatherings controllers : `starts_at.to_time` (TimeWithZone → Time)
#
# Ces exemples figent le comportement OBSERVÉ sous Rails 7.2 avant la montée.
# Ils doivent rester verts À L'IDENTIQUE sous Rails 8.0 : un rouge ici signale
# un glissement d'heure silencieux sur le métier — à corriger au SITE D'APPEL
# (sémantique explicite), jamais en ajustant la capture.
#
# ENV["TZ"] est forcé à UTC pour simuler le serveur (Linode) : c'est là que
# fuseau système (UTC) et fuseau applicatif (Brussels) divergent — sur la
# machine de dev belge, les deux coïncident et masquent tout.
RSpec.describe "to_time — capture fuseau (epic #144)" do
  around do |example|
    previous_tz = ENV["TZ"]
    ENV["TZ"] = "UTC"
    example.run
  ensure
    ENV["TZ"] = previous_tz
  end

  describe "Date#to_time (Reservation#start_time, SpaceReservation#start_time)" do
    it "été : minuit dans le fuseau SYSTÈME (UTC serveur), pas celui de l'app" do
      t = Date.new(2026, 8, 15).to_time
      expect(t.hour).to eq(0)
      expect(t.utc_offset).to eq(0)
    end

    it "hiver : même sémantique de part et d'autre de la bascule DST" do
      t = Date.new(2026, 1, 15).to_time
      expect(t.hour).to eq(0)
      expect(t.utc_offset).to eq(0)
    end

    it "sur le modèle réel : Reservation#start_time == minuit système du jour" do
      reservation = Reservation.new(date: Date.new(2026, 8, 15))
      expect(reservation.start_time).to eq(Time.new(2026, 8, 15, 0, 0, 0, 0))
    end
  end

  describe "TimeWithZone#to_time (events/gatherings controllers)" do
    it "été : même instant, offset Bruxelles (+02:00) préservé" do
      Time.use_zone("Brussels") do
        twz = Time.zone.local(2026, 8, 15, 14, 30)
        t = twz.to_time
        expect(t).to eq(twz)
        expect(t.utc_offset).to eq(2 * 3600)
        expect(t.hour).to eq(14)
      end
    end

    it "hiver : même instant, offset Bruxelles (+01:00) préservé" do
      Time.use_zone("Brussels") do
        twz = Time.zone.local(2026, 1, 15, 14, 30)
        t = twz.to_time
        expect(t).to eq(twz)
        expect(t.utc_offset).to eq(1 * 3600)
        expect(t.hour).to eq(14)
      end
    end
  end
end
