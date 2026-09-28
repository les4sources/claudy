# Ligne de garde : Twilio appelle ce webhook à chaque appel entrant sur notre
# numéro +32, puis à la fin de chaque <Dial> (`dial_status`). La réponse est du
# TwiML qui redirige vers le veilleur de garde (cf. `OnCall::CallFlow`).
#
# Pas de session ni de CSRF, mais une signature Twilio obligatoire : sans elle,
# n'importe qui pourrait lire qui est de garde et composer ses numéros.
class Webhooks::TwilioVoiceController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :verify_twilio_signature

  def incoming
    render_twiml { OnCall::CallFlow.new(params: twilio_params).incoming }
  end

  def dial_status
    render_twiml { OnCall::CallFlow.new(params: twilio_params).dial_status(params[:step].to_s) }
  end

  private

  # Aucune exception ne doit faire tomber l'appel : on logue et on renvoie
  # quand même un TwiML valide (secours ou message).
  def render_twiml
    twiml = begin
      yield
    rescue StandardError => error
      Rails.logger.error("[TwilioVoice] #{error.class}: #{error.message}")
      Sentry.capture_exception(error)
      record_error(error)
      OnCall::CallFlow.emergency_twiml
    end
    render xml: twiml
  end

  def record_error(error)
    return if params[:CallSid].blank?

    call = PhoneCall.find_or_initialize_by(call_sid: params[:CallSid])
    call.from_number ||= params[:From]
    call.update(outcome: "error", error: "#{error.class}: #{error.message}")
  rescue StandardError
    nil
  end

  def twilio_params
    params.permit(:CallSid, :From, :DialCallStatus, :DialCallDuration).to_h.symbolize_keys
  end

  # Twilio signe l'URL exacte configurée dans la console (https) + les
  # paramètres POST. Derrière le reverse proxy de Hatchbox, Rails peut voir la
  # requête en http : on accepte donc aussi la variante https de la même URL.
  # La signature reste un HMAC du jeton — ce choix n'ouvre rien.
  def verify_twilio_signature
    token = OnCall::Config.auth_token
    signature = request.headers["X-Twilio-Signature"].to_s
    head :forbidden and return if token.nil? || signature.empty?

    validator = Twilio::Security::RequestValidator.new(token)
    valid = candidate_urls.any? { |url| validator.validate(url, request.request_parameters, signature) }
    head :forbidden unless valid
  end

  def candidate_urls
    url = request.original_url
    [url, url.sub(/\Ahttp:/, "https:")].uniq
  end
end
