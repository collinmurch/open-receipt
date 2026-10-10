import XCTest

@testable import open_receipt

@MainActor
final class ContactPhotosTests: XCTestCase {
  func testLoadedPhotoIsKept() async {
    let photos = ContactPhotos(client: makeClient { _ in Data([1, 2, 3]) })

    await photos.load("1")

    XCTAssertEqual(photos["1"], Data([1, 2, 3]))
  }

  func testPhotoIsFetchedOnce() async {
    let fetches = CallCounter()
    let photos = ContactPhotos(
      client: makeClient { _ in
        await fetches.increment()
        return nil
      })

    await photos.load("1")
    await photos.load("1")

    let count = await fetches.value
    XCTAssertEqual(count, 1)
  }

  func testFailedFetchIsTriedAgain() async {
    let fetches = CallCounter()
    let photos = ContactPhotos(
      client: makeClient { _ in
        await fetches.increment()
        throw TestError.failed
      })

    await photos.load("1")
    await photos.load("1")

    let count = await fetches.value
    XCTAssertEqual(count, 2)
  }

  func testPhotoIsNotFetchedWithoutContactsAccess() async {
    let fetches = CallCounter()
    let photos = ContactPhotos(
      client: makeClient(status: .denied) { _ in
        await fetches.increment()
        return Data([1])
      })

    await photos.load("1")

    let count = await fetches.value
    XCTAssertEqual(count, 0)
    XCTAssertNil(photos["1"])
  }

  func testMissingIdentifierHasNoPhoto() {
    let photos = ContactPhotos(client: makeClient { _ in Data([1]) })

    XCTAssertNil(photos[nil])
  }

  private func makeClient(
    status: ContactAuthorization = .authorized,
    fetchAvatar: @escaping @Sendable (String) async throws -> Data?
  ) -> ContactClient {
    ContactClient(
      authorizationStatus: { status },
      requestAccess: { status },
      fetchContacts: { _ in [] },
      fetchAvatar: fetchAvatar)
  }
}
