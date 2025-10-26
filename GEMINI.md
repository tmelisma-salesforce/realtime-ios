# GEMINI.md

## Project Overview

This is a native iOS application built with Swift and SwiftUI. It uses the Salesforce Mobile SDK for core functionality, including:

*   **Authentication:** Logging in to a Salesforce organization.
*   **Real-time Data Access:** Using REST API calls to fetch data directly from Salesforce.

The application displays a list of Opportunities from Salesforce using real-time REST API calls without caching or offline storage.

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
    *   **Views:** SwiftUI views are used for the UI (e.g., `OpportunitiesListView`).
    *   **ViewModels:** ViewModels (e.g., `OpportunitiesListModel`) contain the business logic and publish data to the views.
    *   **Models:** Simple data structures (e.g., `Opportunity`) represent the data.
*   **Salesforce Integration:** The Salesforce Mobile SDK is used for all interactions with Salesforce.
    *   `RestClient` is used for real-time REST API calls to fetch data from Salesforce.
    *   No offline storage or caching is implemented - all data is fetched directly from Salesforce on demand.
