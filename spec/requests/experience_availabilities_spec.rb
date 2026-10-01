require "rails_helper"

# Passe UX "mois complet + frame" : la fiche activité affiche un calendrier
# MENSUEL des disponibilités enrobé dans un Turbo Frame. Poser / retirer un
# créneau répond en turbo_stream (pas de rechargement, scroll conservé) avec
# repli HTML (redirect) pour le no-JS. La navigation de mois recharge le frame.
RSpec.describe "Disponibilités d'activité (calendrier mensuel)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(email: "porteur@les4sources.be", password: "password123") }
  let(:experience) { Experience.create!(name: "Balade en forêt", duration_hours: 2) }
  let(:month_start) { Date.today.beginning_of_month }
  # Les créneaux à poser vivent le mois PROCHAIN, dont chaque jour est futur :
  # « le 15 du mois courant ou demain » tombait hors de la grille affichée le
  # dernier jour du mois (échec constaté le 2026-09-30).
  let(:future_month) { Date.today.next_month.beginning_of_month }
  let(:future_month_param) { future_month.strftime("%Y-%m") }
  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

  before { sign_in user }

  # Nombre de cases pour un créneau donné = nombre de jours du mois affiché.
  def day_columns(body, slot: "08:00")
    body.scan(/data-availability-slot="\d{4}-\d{2}-\d{2} #{Regexp.escape(slot)}"/).size
  end

  describe "GET /experiences/:id" do
    it "rend le calendrier du mois en cours dans un Turbo Frame" do
      get experience_path(experience)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="experience_availabilities"')
      expect(response.body).to include('data-month-calendar')
      expect(response.body).to include("Calendrier des disponibilités")
    end

    it "affiche une colonne par jour du mois (28 à 31)" do
      get experience_path(experience)

      # Une case "08:00" par jour du mois affiché.
      expect(day_columns(response.body)).to eq(month_start.end_of_month.day)
      expect(response.body).to include("#{month_start.iso8601} 08:00")
      expect(response.body).to include("#{month_start.end_of_month.iso8601} 08:00")
    end

    it "navigue vers un autre mois via ?month=YYYY-MM" do
      other = (month_start >> 2) # deux mois plus tard
      get experience_path(experience, month: other.strftime("%Y-%m"))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("#{other.iso8601} 08:00")
      expect(day_columns(response.body)).to eq(other.end_of_month.day)
    end

    it "invite à renseigner la durée quand l'activité n'en a pas" do
      no_duration = Experience.create!(name: "Atelier sans durée")
      get experience_path(no_duration)

      expect(response.body).to include("durée de l&#39;activité")
      expect(response.body).not_to include("data-availability-slot")
    end

    it "marque le créneau posé comme occupé" do
      # Un jour futur du mois courant pour éviter la case "past".
      future_day = future_month + 15
      experience.experience_availabilities.create!(available_on: future_day, starts_at: "10:00")

      get experience_path(experience, month: future_month_param)

      expect(response.body).to include('data-availability-state="taken"')
    end
  end

  describe "POST — poser un bloc" do
    let(:target_day) { future_month + 20 }

    it "répond en turbo_stream et le frame contient le nouveau créneau (occupé)" do
      expect {
        post experience_experience_availabilities_path(experience, month: future_month_param),
             params: { experience_availability: { available_on: target_day.iso8601, starts_at: "14:00" } },
             headers: turbo_headers
      }.to change(ExperienceAvailability, :count).by(1)

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include('id="experience_availabilities"')
      expect(response.body).to include('data-availability-state="taken"')

      availability = ExperienceAvailability.last
      expect(availability.duration_minutes).to eq(120)
    end

    it "repli HTML : redirige vers le mois affiché pour le no-JS" do
      week_param = future_month_param

      post experience_experience_availabilities_path(experience, month: week_param),
           params: { experience_availability: { available_on: target_day.iso8601, starts_at: "16:00" } },
           headers: { "Accept" => "text/html" }

      expect(response).to redirect_to(experience_path(experience, month: week_param))
    end

    it "refuse un chevauchement et le signale" do
      experience.experience_availabilities.create!(available_on: target_day, starts_at: "10:00")

      expect {
        post experience_experience_availabilities_path(experience, month: future_month_param),
             params: { experience_availability: { available_on: target_day.iso8601, starts_at: "11:00" } }
      }.not_to change(ExperienceAvailability, :count)

      expect(flash[:alert]).to match(/chevauche/)
    end
  end

  # Rattraper une activité tenue sans créneau posé : l'équipe peut poser un
  # bloc dans le passé ; un porteur restreint, non.
  describe "jours passés" do
    let(:past_month) { Date.today.prev_month.beginning_of_month }
    let(:past_month_param) { past_month.strftime("%Y-%m") }
    let(:past_day) { past_month + 10 }

    it "propose des cases libres sur les jours passés à l'équipe" do
      get experience_path(experience, month: past_month_param)

      expect(response.body).to include(%(data-availability-slot="#{past_day.iso8601} 08:00" data-availability-state="free"))
      expect(response.body).not_to include('data-availability-state="past"')
    end

    it "laisse l'équipe poser un créneau à une date passée" do
      expect {
        post experience_experience_availabilities_path(experience, month: past_month_param),
             params: { experience_availability: { available_on: past_day.iso8601, starts_at: "10:00" } },
             headers: turbo_headers
      }.to change(ExperienceAvailability, :count).by(1)
    end

    context "porteur restreint" do
      let(:carrier) { Human.create!(name: "Porteur") }
      let(:user) do
        User.create!(email: "porteur@les4sources.be", password: "password123",
                     human: carrier, restricted_to_experiences: true)
      end
      let(:experience) { Experience.create!(name: "Balade en forêt", duration_hours: 2, human: carrier) }

      it "verrouille les jours passés de sa grille" do
        get experience_path(experience, month: past_month_param)

        expect(response.body).to include('data-availability-state="past"')
      end

      it "refuse un créneau à une date passée" do
        expect {
          post experience_experience_availabilities_path(experience, month: past_month_param),
               params: { experience_availability: { available_on: past_day.iso8601, starts_at: "10:00" } }
        }.not_to change(ExperienceAvailability, :count)

        expect(flash[:alert]).to match(/date passée/)
      end
    end
  end

  describe "DELETE — retirer un bloc" do
    let(:target_day) { future_month + 22 }

    it "supprime en turbo_stream et remplace le frame" do
      availability = experience.experience_availabilities.create!(available_on: target_day, starts_at: "16:00")

      expect {
        delete experience_experience_availability_path(experience, availability, month: future_month_param),
               headers: turbo_headers
      }.to change(ExperienceAvailability, :count).by(-1)

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include('id="experience_availabilities"')
    end

    it "repli HTML : redirige vers le mois affiché pour le no-JS" do
      availability = experience.experience_availabilities.create!(available_on: target_day, starts_at: "18:00")

      delete experience_experience_availability_path(experience, availability, month: future_month_param),
             headers: { "Accept" => "text/html" }

      expect(response).to redirect_to(experience_path(experience, month: future_month_param))
    end
  end
end
