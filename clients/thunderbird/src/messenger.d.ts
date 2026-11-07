// The part of Thunderbird's WebExtension API (Manifest V3) this extension
// uses. The published typings trail Thunderbird and describe Manifest V2.

declare namespace messenger {
  interface MessageHeader {
    id: number;
    headerMessageId: string;
    subject: string;
    author: string;
    date: Date;
  }

  interface MessageList {
    id: string | null;
    messages: MessageHeader[];
  }

  namespace messages {
    function listInlineTextParts(messageId: number): Promise<{ contentType: string; content: string }[]>;
    function continueList(messageListId: string): Promise<MessageList>;
  }

  namespace messageDisplay {
    function getDisplayedMessages(tabId?: number): Promise<MessageList>;
  }

  namespace messengerUtilities {
    function convertToPlainText(body: string, options?: { flowed?: boolean }): Promise<string>;
  }

  namespace tabs {
    function query(query: { active?: boolean; currentWindow?: boolean }): Promise<{ id?: number }[]>;
  }

  namespace menus {
    interface OnClickData {
      menuItemId: string | number;
      selectedMessages?: MessageList;
    }
    function create(properties: { id: string; title: string; contexts: string[] }): void;
    const onClicked: { addListener(listener: (info: OnClickData) => void): void };
  }

  namespace runtime {
    function openOptionsPage(): Promise<void>;
    const onInstalled: { addListener(listener: () => void): void };
  }

  namespace notifications {
    function create(options: { type: "basic"; title: string; message: string; iconUrl?: string }): Promise<string>;
  }

  namespace windows {
    function openDefaultBrowser(url: string): Promise<void>;
  }
}
