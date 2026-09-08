json.generated_at Time.current.utc.iso8601
json.experiences @experiences do |experience|
  json.partial! "api/public/v1/experiences/experience",
                experience: experience,
                availabilities: @availabilities.fetch(experience.id, [])
end
