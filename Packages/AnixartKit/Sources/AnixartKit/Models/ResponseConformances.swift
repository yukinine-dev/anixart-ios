// Conformances for the generated response envelopes.
// Every Anixart response extends `Response` in the Android client, which means it
// carries a `code` field; `AnixartClient` uses this conformance to turn a non-zero
// code into an `AnixartError.api`.

import Foundation

extension CollectionResponse: AnixartResponse {}
extension EpisodeResponse: AnixartResponse {}
extension GoogleResponse: AnixartResponse {}
extension ProfileResponse: AnixartResponse {}
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
