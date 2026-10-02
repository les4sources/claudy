module OnCall
  # Le TwiML de la ligne de garde. Un appel descend une cascade de marches :
  #
  #   1. le veilleur de garde ;
  #   2. le suppléant du jour ;
  #   3. le numéro de secours (`TWILIO_FALLBACK_NUMBER`) ;
  #   4. un court message vocal en français, puis on raccroche.
  #
  # Chaque <Dial> renvoie son issue à `dial_status` via son attribut `action` ;
  # si personne n'a décroché, on passe à la marche suivante. Une marche sans
  # numéro est sautée, et un même numéro n'est jamais composé deux fois.
  #
  # Le `callerId` de chaque <Dial> est TOUJOURS notre numéro Twilio +32 : c'est
  # lui qui fixe le tarif de la jambe sortante. Sans ce numéro configuré, on ne
  # compose rien et on joue le message.
  class CallFlow
    # 18 s : la messagerie des opérateurs belges décroche vers 20-25 s ; au-delà,
    # elle « répond » à la place du veilleur et la cascade s'arrête.
    DIAL_TIMEOUT = 18
    STEPS = %w[on_call backup fallback].freeze
    ANSWERED_STATUSES = %w[completed answered].freeze
    ACTION_PATH = "/webhooks/twilio/voice/dial_status".freeze
    MESSAGE = "Bonjour, vous êtes bien aux 4 Sources. Personne n'est disponible " \
              "pour le moment. Merci de rappeler un peu plus tard. Belle journée !".freeze

    Target = Struct.new(:step, :number, :human)

    # TwiML de dernier recours, construit sans base ni planning : le secours
    # s'il est configuré, sinon le message. Sert quand une exception survient.
    def self.emergency_twiml
      response = Twilio::TwiML::VoiceResponse.new
      caller_id = Config.twilio_phone_number
      fallback = Config.fallback_number
      if caller_id && fallback
        response.dial(caller_id: caller_id, timeout: DIAL_TIMEOUT) { |dial| dial.number(fallback) }
      else
        response.say(message: MESSAGE, language: "fr-FR")
      end
      response.hangup
      response.to_s
    end

    def initialize(params:, at: Time.current)
      @params = params
      @at = at
    end

    # Premier webhook : l'appel arrive.
    def incoming
      call = PhoneCall.find_or_create_by!(call_sid: call_sid) do |record|
        record.from_number = @params[:From]
        record.duty_date = resolver_for(nil).duty_date
        record.on_call_human = resolver_for(nil).on_call
      end
      next_twiml(call, after: nil)
    end

    # Webhook `action` d'un <Dial> : la marche `step` vient de se terminer.
    def dial_status(step)
      return hangup_twiml unless STEPS.include?(step)

      call = PhoneCall.find_by(call_sid: call_sid) ||
             PhoneCall.create!(call_sid: call_sid, from_number: @params[:From],
                               duty_date: resolver_for(nil).duty_date)
      status = @params[:DialCallStatus].presence
      duration = @params[:DialCallDuration].presence&.to_i
      call.complete_attempt!(step: step, status: status, duration: duration)

      if ANSWERED_STATUSES.include?(status)
        call.update!(outcome: "answered_#{step}")
        hangup_twiml
      else
        next_twiml(call, after: step)
      end
    end

    private

    def call_sid = @params[:CallSid].presence || raise(ArgumentError, "CallSid manquant")

    def resolver_for(call)
      @resolver ||= call&.duty_date ? Resolver.new(duty_date: call.duty_date) : Resolver.new(at: @at)
    end

    def next_twiml(call, after:)
      caller_id = Config.twilio_phone_number
      target = caller_id && next_target(call, after)

      if target
        call.record_attempt!(step: target.step, human: target.human, number: target.number)
        dial_twiml(target, caller_id)
      else
        call.update!(outcome: "unanswered")
        message_twiml
      end
    end

    def next_target(call, after)
      dialed = call.attempts.map { |entry| entry["number"] }
      index = STEPS.index(after.to_s)
      remaining = after.nil? ? STEPS : (index ? STEPS.drop(index + 1) : [])
      remaining.lazy.map { |step| target_for(step, call) }
               .find { |target| target && !dialed.include?(target.number) }
    end

    def target_for(step, call)
      resolver = resolver_for(call)
      case step
      when "on_call"
        human = resolver.on_call
        human && Target.new(step, human.phone, human)
      when "backup"
        human = resolver.backup
        human && Target.new(step, human.phone, human)
      when "fallback"
        number = Config.fallback_number
        number && Target.new(step, number, nil)
      end
    end

    def dial_twiml(target, caller_id)
      response = Twilio::TwiML::VoiceResponse.new
      response.dial(caller_id: caller_id, timeout: DIAL_TIMEOUT,
                    action: "#{ACTION_PATH}?step=#{target.step}", method: "POST") do |dial|
        dial.number(target.number)
      end
      response.to_s
    end

    def message_twiml
      response = Twilio::TwiML::VoiceResponse.new
      response.say(message: MESSAGE, language: "fr-FR")
      response.hangup
      response.to_s
    end

    def hangup_twiml
      Twilio::TwiML::VoiceResponse.new.tap(&:hangup).to_s
    end
  end
end
