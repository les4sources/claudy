require "rails_helper"

# Epic #244, phase 2 — la tenue de l'activité. Confirmée n'est pas tenue.
RSpec.describe "Tenue des activités", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:porteuse) { Human.create!(name: "Ada", email: "ada@les4sources.be", status: "active") }
  let(:autre) { Human.create!(name: "Bob", email: "bob@les4sources.be", status: "active") }
  let(:user_porteuse) { User.create!(email: "ada@les4sources.be", password: "password123", human: porteuse) }
  let(:admin) { User.create!(email: "admin@les4sources.be", password: "password123") }

  let(:experience) { Experience.create!(name: "Atelier vannerie", human: porteuse, duration_hours: 2) }
  let(:experience_autre) { Experience.create!(name: "Balade contée", human: autre, duration_hours: 1) }
  let(:customer) { Customer.create!(email: "client@example.com", first_name: "Léa", customer_type: "individual") }
  let(:stay) do
    Stay.create!(customer: customer, status: "confirmed",
                 arrival_date: Date.current - 20, departure_date: Date.current - 18)
  end

  def slot(experience, on:)
    ExperienceAvailability.create!(experience: experience, available_on: on,
                                   starts_at: "10:00", duration_minutes: 120)
  end

  def booking(experience:, on: Date.current - 10, status: "confirmed")
    ExperienceBooking.create!(experience_availability: slot(experience, on: on), stay: stay,
                              participants: 2, status: status)
  end

  describe "le modèle" do
    it "refuse un verdict sur une activité non confirmée" do
      pendante = booking(experience: experience, status: "pending")

      expect { pendante.mark_held! }.to raise_error(ExperienceBooking::OutcomeNotRecordable)
      expect(pendante.reload.outcome).to be_nil
    end

    it "refuse un verdict sur un créneau encore à venir" do
      future = booking(experience: experience, on: Date.current + 5)

      expect { future.mark_held! }.to raise_error(ExperienceBooking::OutcomeNotRecordable, /pas encore eu lieu/)
    end

    it "note qui a répondu et quand" do
      passee = booking(experience: experience)

      passee.mark_held!(by: porteuse)

      expect(passee.reload.outcome).to eq("held")
      expect(passee.outcome_recorded_by).to eq(porteuse)
      expect(passee.outcome_recorded_at).to be_present
      expect(passee.outcome_label).to eq("A eu lieu")
    end

    it "sort de la file dès qu'un verdict est posé" do
      passee = booking(experience: experience)
      expect(ExperienceBooking.awaiting_outcome).to include(passee)

      passee.mark_no_show!
      expect(ExperienceBooking.awaiting_outcome).not_to include(passee)
    end
  end

  describe "l'écran « À confirmer »" do
    it "ne montre au porteur que SES créneaux passés sans verdict" do
      mienne = booking(experience: experience)
      pas_la_mienne = booking(experience: experience_autre)
      sign_in user_porteuse

      get outcomes_experience_bookings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Atelier vannerie")
      expect(response.body).not_to include("Balade contée")
      expect(mienne).to be_present
      expect(pas_la_mienne).to be_present
    end

    it "n'offre la sélection multiple qu'à l'admin global" do
      booking(experience: experience)

      sign_in user_porteuse
      get outcomes_experience_bookings_path
      expect(response.body).not_to include("Sélection multiple")

      sign_in admin
      get outcomes_experience_bookings_path
      expect(response.body).to include("Sélection multiple")
    end

    it "le dit quand il n'y a rien à confirmer" do
      sign_in admin
      get outcomes_experience_bookings_path
      expect(response.body).to include("Rien à confirmer")
    end
  end

  describe "poser un verdict" do
    it "marque « a eu lieu »" do
      passee = booking(experience: experience)
      sign_in user_porteuse

      patch record_outcome_experience_booking_path(passee, outcome: "held")

      expect(passee.reload).to be_held
      expect(passee.outcome_recorded_by).to eq(porteuse)
    end

    it "refuse le créneau d'un autre porteur (404, sans rien divulguer)" do
      pas_la_mienne = booking(experience: experience_autre)
      sign_in user_porteuse

      patch record_outcome_experience_booking_path(pas_la_mienne, outcome: "held")

      expect(pas_la_mienne.reload.outcome).to be_nil
    end

    it "tranche en masse pour l'admin global" do
      a = booking(experience: experience)
      b = booking(experience: experience_autre)
      sign_in admin

      post bulk_outcome_experience_bookings_path,
           params: { experience_booking_ids: [a.id, b.id], outcome: "held" }

      expect(a.reload).to be_held
      expect(b.reload).to be_held
      expect(flash[:notice]).to include("2 activité(s)")
    end

    it "n'applique le geste en masse qu'aux créneaux recevables, et nomme les autres" do
      passee = booking(experience: experience)
      future = booking(experience: experience, on: Date.current + 3)
      sign_in admin

      post bulk_outcome_experience_bookings_path,
           params: { experience_booking_ids: [passee.id, future.id], outcome: "held" }

      expect(passee.reload).to be_held
      expect(future.reload.outcome).to be_nil
      expect(flash[:alert]).to include("Atelier vannerie")
    end
  end

  describe "le badge « À confirmer »" do
    it "apparaît sur l'index des activités avec le compte" do
      booking(experience: experience)
      sign_in user_porteuse

      get experience_bookings_path

      expect(response.body).to include("À confirmer (1)")
    end

    it "disparaît quand tout est tranché" do
      booking(experience: experience).mark_held!
      sign_in user_porteuse

      get experience_bookings_path

      expect(response.body).not_to include("À confirmer (")
    end
  end

  describe "le canal jeton" do
    it "affiche la page de confirmation, et ne mute rien sur le GET" do
      passee = booking(experience: experience)

      get activity_outcome_path(passee.outcome_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Atelier vannerie", "Oui, elle a eu lieu")
      expect(passee.reload.outcome).to be_nil
    end

    it "enregistre la tenue sur le POST, et reste idempotent" do
      passee = booking(experience: experience)
      jeton = passee.outcome_token

      post activity_outcome_held_path(jeton)
      expect(passee.reload).to be_held
      pose_a = passee.outcome_recorded_at

      post activity_outcome_held_path(jeton)
      expect(passee.reload.outcome_recorded_at).to eq(pose_a)
    end

    it "renvoie 404 sur un jeton inconnu" do
      get activity_outcome_path("nimportequoi")
      expect(response).to have_http_status(:not_found)
    end

    it "refuse un jeton de VALIDATION : les portées ne se mélangent pas" do
      passee = booking(experience: experience)

      get activity_outcome_path(passee.validation_token)

      expect(response).to have_http_status(:not_found)
    end

    it "exige une connexion pour « n'a pas eu lieu »" do
      passee = booking(experience: experience)

      get activity_outcome_no_show_path(passee.outcome_token)

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "le rappel" do
    it "groupe UN email par porteur, et ne part pas en dry-run" do
      booking(experience: experience)
      booking(experience: experience, on: Date.current - 4)

      expect { Activities::OutcomeReminders.new(dry_run: true).run }
        .not_to change { ActionMailer::Base.deliveries.size }

      result = Activities::OutcomeReminders.new(dry_run: false).run

      expect(result.carriers.size).to eq(1)
      expect(result.bookings_count).to eq(2)
      expect(ActionMailer::Base.deliveries.last.subject).to include("2 activités à confirmer")
      expect(ActionMailer::Base.deliveries.last.to).to eq(["ada@les4sources.be"])
    end

    it "signale un porteur sans email plutôt que de lever" do
      sans_email = Human.create!(name: "Sans mail", status: "active")
      exp = Experience.create!(name: "Atelier muet", human: sans_email, duration_hours: 1)
      booking(experience: exp)

      result = Activities::OutcomeReminders.new(dry_run: false).run

      expect(result.skipped.join).to include("Sans mail")
    end
  end
end
