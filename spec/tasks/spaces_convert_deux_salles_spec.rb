require "rails_helper"
require "rake"

# Conversion de l'historique « Les 2 salles » en paires Grande + Petite salle
# (décision Michael 2026-07-20). Chaque SpaceReservation vivante sur l'espace
# « Les 2 salles » devient DEUX réservations (Grande + Petite, même date, même
# duration) sur le MÊME SpaceBooking ; l'originale est détruite ; le prix du
# SpaceBooking reste inchangé. En fin d'APPLY, l'espace est soft-deleté.
RSpec.describe "spaces:convert_deux_salles", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("spaces:convert_deux_salles")
  end

  def run_task(apply: false)
    task = Rake::Task["spaces:convert_deux_salles"]
    task.reenable
    previous_apply = ENV["APPLY"]
    ENV["APPLY"] = apply ? "1" : nil
    original = $stdout
    $stdout = StringIO.new
    task.invoke
    $stdout.string
  ensure
    $stdout = original
    ENV["APPLY"] = previous_apply
  end

  let!(:deux)   { Space.create!(name: "Les 2 salles", code: "T+S", capacity: 1) }
  let!(:grande) { Space.create!(name: "Grande Salle", code: "TIL", capacity: 1) }
  let!(:petite) { Space.create!(name: "Petite Salle", code: "SAU", capacity: 1) }

  let(:from) { Date.new(2024, 6, 1) }
  let(:to)   { Date.new(2024, 6, 2) }

  def build_space_booking(status: "confirmed", price_cents: 43_000)
    SpaceBooking.create!(firstname: "Ada", group_name: "Les Analytiques",
                         from_date: from, to_date: to, status: status,
                         price_cents: price_cents)
  end

  context "DRY-RUN (par défaut)" do
    it "n'écrit rien : ni conversion, ni suppression, ni soft-delete" do
      sb = build_space_booking
      sb.space_reservations.create!(space: deux, date: from, duration: "day")

      expect { run_task(apply: false) }.not_to change(SpaceReservation, :count)
      expect(sb.space_reservations.reload.map(&:space_id)).to eq([deux.id])
      expect(Space.exists?(deux.id)).to be(true)
    end
  end

  context "APPLY — conversion d'une réservation" do
    it "remplace la résa par une paire Grande + Petite (même date, même duration), prix conservé" do
      sb = build_space_booking(price_cents: 43_000)
      sb.space_reservations.create!(space: deux, date: from, duration: "fullday")

      run_task(apply: true)

      reservations = sb.space_reservations.reload
      expect(reservations.map(&:space_id)).to contain_exactly(grande.id, petite.id)
      expect(reservations.map(&:date).uniq).to eq([from])
      expect(reservations.map(&:duration).uniq).to eq(["fullday"])
      expect(sb.reload.price_cents).to eq(43_000)     # total INCHANGÉ
      expect(SpaceReservation.where(space_id: deux.id)).to be_empty
    end

    it "convertit plusieurs réservations du même booking (N → 2N)" do
      sb = build_space_booking
      sb.space_reservations.create!(space: deux, date: from, duration: "day")
      sb.space_reservations.create!(space: deux, date: to, duration: "evening")

      run_task(apply: true)

      expect(sb.space_reservations.reload.count).to eq(4)
      expect(sb.space_reservations.where(space_id: grande.id).pluck(:date)).to contain_exactly(from, to)
    end
  end

  context "collision de capacité (jour déjà réservé séparément)" do
    it "convertit quand même MAIS liste la collision (non bloquant)" do
      # Une Grande Salle déjà réservée (confirmée) le même jour → dépassement.
      other = build_space_booking
      other.space_reservations.create!(space: grande, date: from, duration: "day")

      sb = build_space_booking
      sb.space_reservations.create!(space: deux, date: from, duration: "day")

      output = run_task(apply: true)

      expect(sb.space_reservations.reload.map(&:space_id)).to contain_exactly(grande.id, petite.id)
      expect(output).to include("Collisions capacité")
      expect(output).to match(/Grande Salle le #{from} déjà réservé/)
    end
  end

  context "soft-delete de l'espace en fin d'APPLY" do
    it "soft-delete « Les 2 salles » quand plus aucune réservation vivante ne le pointe" do
      sb = build_space_booking
      sb.space_reservations.create!(space: deux, date: from, duration: "day")

      run_task(apply: true)

      expect(Space.exists?(deux.id)).to be(false)          # hors du default_scope
      expect(Space.unscoped.find(deux.id).deleted_at).to be_present
    end
  end

  context "idempotence" do
    it "un second APPLY ne crée aucune nouvelle réservation" do
      sb = build_space_booking
      sb.space_reservations.create!(space: deux, date: from, duration: "day")

      run_task(apply: true)
      expect { run_task(apply: true) }.not_to change(SpaceReservation, :count)
    end
  end
end
