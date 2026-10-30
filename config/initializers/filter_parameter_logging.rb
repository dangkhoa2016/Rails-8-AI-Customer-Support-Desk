Rails.application.config.filter_parameters += %i[
  passw token secret api_key authorization cookie session payment card pin
  authenticity_token body initial_message draft_reply query preview_password
  code otp one_time_code mfa_secret recovery_code
]
