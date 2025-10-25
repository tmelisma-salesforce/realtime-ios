# GEMINI.md

## Project Overview

This is a native iOS application built with Swift and SwiftUI. It uses the Salesforce Mobile SDK for core functionality, including:

*   **Authentication:** Logging in to a Salesforce organization.
*   **Data Storage:** Using SmartStore, a secure offline database, to store Salesforce data.
*   **Data Synchronization:** Using MobileSync to synchronize data between the Salesforce cloud and the local SmartStore.

The application displays a list of Accounts from Salesforce and allows the user to view the Contacts associated with each Account.

## Building and Running

To build and run this project, you will need Xcode and the CocoaPods dependency manager.

1.  **Install Dependencies:**
    ```bash
    pod install
    ```

2.  **Open the Workspace:**
    Open the `Realtime.xcworkspace` file in Xcode.

3.  **Run the App:**
    Select a simulator or a connected device and click the "Run" button in Xcode.

## Development Conventions

*   **Language:** The application is written in Swift.
*   **UI:** The user interface is built with SwiftUI.
*   **Architecture:** The app uses a Model-View-ViewModel (MVVM) architecture.
    *   **Views:** SwiftUI views are used for the UI (e.g., `AccountsListView`, `ContactsForAccountListView`).
    *   **ViewModels:** ViewModels (e.g., `AccountsListModel`, `ContactsForAccountModel`) contain the business logic and publish data to the views.
    *   **Models:** Simple data structures (e.g., `Account`, `Contact`) represent the data.
*   **Salesforce Integration:** The Salesforce Mobile SDK is used for all interactions with Salesforce.
    *   `SmartStore` is used for local data storage.
    *   `MobileSync` is used to synchronize data with Salesforce.
    *   The `userstore.json` and `usersyncs.json` files configure the SmartStore and MobileSync settings.
