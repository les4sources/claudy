# Un appel reçu sur la ligne de garde (Twilio). Sert au suivi et au contrôle
# des coûts ; aucun audio n'est enregistré. `attempts` liste chaque <Dial> de
# la cascade : { step, human_id, number, status, duration }.
class PhoneCall < ApplicationRecord
  OUTCOME_LABELS = {
    "answered_on_call" => "Répondu par le veilleur",
    "answered_backup" => "Répondu par le suppléant",
    "answered_fallback" => "Répondu par le secours",
    "unanswered" => "Personne n'a décroché — message joué",
    "error" => "Erreur — secours déclenché"
  }.freeze
  OUTCOMES = OUTCOME_LABELS.keys.freeze

  STEP_LABELS = { "on_call" => "Veilleur", "backup" => "Suppléant", "fallback" => "Secours" }.freeze

  belongs_to :on_call_human, -> { unscope(where: [:deleted_at, :status]) },
             class_name: "Human", optional: true

  validates :call_sid, presence: true, uniqueness: true
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }

  # Sans issue : l'appel sonne encore, ou l'appelant a raccroché avant que
  # Twilio ne rappelle l'`action` du <Dial>.
  def outcome_label
    OUTCOME_LABELS.fetch(outcome.to_s, "En cours ou interrompu")
  end

  def record_attempt!(step:, human: nil, number:, status: nil, duration: nil)
    entry = { "step" => step.to_s, "human_id" => human&.id, "number" => number,
              "status" => status, "duration" => duration }
    update!(attempts: attempts + [entry])
  end

  # Complète la dernière tentative avec ce que Twilio renvoie à l'`action`.
  def complete_attempt!(step:, status:, duration:)
    list = attempts.map(&:dup)
    last = list.reverse.find { |entry| entry["step"] == step.to_s && entry["status"].nil? }
    last&.merge!("status" => status, "duration" => duration)
    update!(attempts: list, dial_call_status: status, dial_call_duration: duration)
  end
end
