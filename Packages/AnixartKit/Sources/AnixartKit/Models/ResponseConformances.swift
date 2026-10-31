// Conformances for the generated response envelopes.
// Every Anixart response extends `Response` in the Android client, which means it
// carries a `code` field; `AnixartClient` uses this conformance to turn a non-zero
// code into an `AnixartError.api`.

import Foundation

extension CollectionResponse: AnixartResponse {}
extension EpisodeResponse: AnixartResponse {}
extension GoogleResponse: AnixartResponse {}
extension ProfileResponse: AnixartResponse {}
extension ProfilePreferenceResponse: AnixartResponse {}
extension ProfileBadgeSectionsResponse: AnixartResponse {}
extension ProfileSelectThemeResponse: AnixartResponse {}
extension ChangeLoginInfoResponse: AnixartResponse {}
extension ChangeLoginResponse: AnixartResponse {}
extension CheckLoginResponse: AnixartResponse {}
extension ProfileBadgeResponse: AnixartResponse {}
extension ChangeEmailResponse: AnixartResponse {}
extension ChangeEmailResendResponse: AnixartResponse {}
extension ChangePasswordResponse: AnixartResponse {}
extension ProfileDeletionResponse: AnixartResponse {}
extension ProfileHealthStatusResponse: AnixartResponse {}
extension ProfileEnforcementResponse: AnixartResponse {}
extension ChannelResponse: AnixartResponse {}
extension ChannelUploadCoverAvatarResponse: AnixartResponse {}
extension ReleaseResponse: AnixartResponse {}
extension ReleaseSearchResponse: AnixartResponse {}
extension RestoreResponse: AnixartResponse {}
extension RestoreVerifyResponse: AnixartResponse {}
extension ScheduleResponse: AnixartResponse {}
extension SignInResponse: AnixartResponse {}
extension SignUpResponse: AnixartResponse {}
extension SourcesResponse: AnixartResponse {}
extension TelegramResponse: AnixartResponse {}
extension TogglesResponse: AnixartResponse {}
extension TypeResponse: AnixartResponse {}
extension TypesResponse: AnixartResponse {}
extension VerifyResponse: AnixartResponse {}
extension VkResponse: AnixartResponse {}
extension YandexResponse: AnixartResponse {}
