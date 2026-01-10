import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Link, Route, Routes } from "react-router-dom";
import "./App.css";

type UploadStatus = "idle" | "uploading" | "done" | "failed";

type SidebarItem = {
  label: string;
  to?: string;
  active?: boolean;
};

type WindowProps = {
  title: string;
  children: ReactNode;
  className?: string;
  onTitleClick?: () => void;
  onTitlePointerDown?: (event: React.PointerEvent<HTMLDivElement>) => void;
  onNotRespondingExit?: () => void;
  onMaximize?: () => void;
  isMaximized?: boolean;
  isNotResponding?: boolean;
  windowStyle?: React.CSSProperties;
  windowRef?: React.RefObject<HTMLDivElement | null>;
};

type WindowShellProps = {
  title: string;
  toolbarLabel: string;
  toolbarValue: string;
  sidebarTitle: string;
  sidebarItems: SidebarItem[];
  footerLabel: string;
  statusLabel: string;
  children: ReactNode;
  onTitleClick?: () => void;
  onTitlePointerDown?: (event: React.PointerEvent<HTMLDivElement>) => void;
  onNotRespondingExit?: () => void;
  onMaximize?: () => void;
  isMaximized?: boolean;
  isNotResponding?: boolean;
  windowStyle?: React.CSSProperties;
  windowRef?: React.RefObject<HTMLDivElement | null>;
};

const RetroWindow = ({
  title,
  children,
  className,
  onTitleClick,
  onTitlePointerDown,
  onNotRespondingExit,
  onMaximize,
  isMaximized,
  isNotResponding,
  windowStyle,
  windowRef,
}: WindowProps) => {
  const handleKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (!onTitleClick) return;
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onTitleClick();
    }
  };

  return (
    <section
      className={`window ${isMaximized ? "maximized" : ""} ${
        isNotResponding ? "not-responding" : ""
      } ${className ?? ""}`.trim()}
      style={windowStyle}
      ref={windowRef}
    >
      <div
        className="title-bar"
        onClick={onTitleClick}
        onKeyDown={handleKeyDown}
        onPointerDown={onTitlePointerDown}
        role="button"
        tabIndex={0}
      >
        <span className="title-text">{title}</span>
        <div className="title-controls" aria-hidden="true">
          <button
            type="button"
            className="control"
            onPointerDown={(event) => event.stopPropagation()}
            disabled={isNotResponding}
          >
            _
          </button>
          <button
            type="button"
            className="control"
            onClick={(event) => {
              event.stopPropagation();
              onMaximize?.();
            }}
            onPointerDown={(event) => event.stopPropagation()}
            disabled={isNotResponding}
          >
            {isMaximized ? "[]" : "[ ]"}
          </button>
          <button
            type="button"
            className="control"
            onPointerDown={(event) => event.stopPropagation()}
            disabled={isNotResponding}
          >
            x
          </button>
        </div>
      </div>
      <div className="window-body">{children}</div>
      {isNotResponding ? (
        <div
          className="not-responding-overlay"
          onClick={onNotRespondingExit}
          role="button"
          aria-label="Resume"
          tabIndex={0}
        />
      ) : null}
    </section>
  );
};

const WindowShell = ({
  title,
  toolbarLabel,
  toolbarValue,
  sidebarTitle,
  sidebarItems,
  footerLabel,
  statusLabel,
  children,
  onTitleClick,
  onTitlePointerDown,
  onNotRespondingExit,
  onMaximize,
  isMaximized,
  isNotResponding,
  windowStyle,
  windowRef,
}: WindowShellProps) => {
  return (
    <RetroWindow
      title={title}
      onTitleClick={onTitleClick}
      onTitlePointerDown={onTitlePointerDown}
      onNotRespondingExit={onNotRespondingExit}
      onMaximize={onMaximize}
      isMaximized={isMaximized}
      isNotResponding={isNotResponding}
      windowStyle={windowStyle}
      windowRef={windowRef}
    >
      <div className="toolbar">
        <span className="toolbar-label">{toolbarLabel}</span>
        <div className="toolbar-select">{toolbarValue}</div>
        <div className="toolbar-buttons">
          <Link to="/info" className="toolbar-icon" aria-label="Info">
            ?
          </Link>
          <span className="toolbar-icon">!</span>
        </div>
      </div>
      <div className="window-content">
        <aside className="sidebar">
          <div className="sidebar-title">{sidebarTitle}</div>
          <div className="sidebar-list">
            {sidebarItems.map((item) => {
              const className = `sidebar-item ${item.active ? "active" : ""}`.trim();
              return item.to ? (
                <Link key={item.label} to={item.to} className={className}>
                  {item.label}
                </Link>
              ) : (
                <div key={item.label} className={className}>
                  {item.label}
                </div>
              );
            })}
          </div>
          <div className="sidebar-footer">{footerLabel}</div>
        </aside>
        <main className="content-panel">{children}</main>
      </div>
      <div className="status-bar">
        <span className="status-text">{statusLabel}</span>
      </div>
    </RetroWindow>
  );
};

type PageProps = {
  windowTitle: string;
  isMaximized: boolean;
  isNotResponding: boolean;
  windowStyle: React.CSSProperties;
  windowRef: React.RefObject<HTMLDivElement | null>;
  onTitleClick: () => void;
  onTitlePointerDown: (event: React.PointerEvent<HTMLDivElement>) => void;
  onNotRespondingExit: () => void;
  onMaximize: () => void;
};

const LandingPage = ({
  windowTitle,
  isMaximized,
  isNotResponding,
  windowStyle,
  windowRef,
  onTitleClick,
  onTitlePointerDown,
  onNotRespondingExit,
  onMaximize,
}: PageProps) => {
  return (
    <WindowShell
      title={windowTitle}
      toolbarLabel="Select a directory:"
      toolbarValue="Parcel"
      sidebarTitle="Parcel"
      sidebarItems={[
        { label: "Landing", active: true },
        { label: "Upload", to: "/upload" },
        { label: "Info", to: "/info" },
      ]}
      footerLabel="Help"
      statusLabel="Ready"
      onTitleClick={onTitleClick}
      onTitlePointerDown={onTitlePointerDown}
      onNotRespondingExit={onNotRespondingExit}
      onMaximize={onMaximize}
      isMaximized={isMaximized}
      isNotResponding={isNotResponding}
      windowStyle={windowStyle}
      windowRef={windowRef}
    >
      <div className="content-stack">
        <div className="content-header">
          <h1>Parcel</h1>
          <p className="subtitle">
            A link-only, anonymous file drop that streams bytes to disk.
          </p>
          <Link to="/upload" className="btn primary">
            Upload a file
          </Link>
        </div>
        <div className="group-box">
          <div className="group-title">How it works</div>
          <ul>
            <li>You upload a file.</li>
            <li>You get an unguessable link.</li>
            <li>Anyone with the link can access it.</li>
          </ul>
        </div>
        <div className="group-box alert">
          <div className="group-title">Limitations</div>
          <ul>
            <li>No accounts.</li>
            <li>No file listing.</li>
            <li>Link possession is access.</li>
          </ul>
        </div>
      </div>
    </WindowShell>
  );
};

type UploadPageProps = PageProps & {
  onStatusChange: (status: UploadStatus) => void;
};

const UploadPage = ({
  windowTitle,
  isMaximized,
  isNotResponding,
  windowStyle,
  windowRef,
  onTitleClick,
  onTitlePointerDown,
  onNotRespondingExit,
  onMaximize,
  onStatusChange,
}: UploadPageProps) => {
  const [file, setFile] = useState<File | null>(null);
  const [status, setStatus] = useState<UploadStatus>("idle");
  const [error, setError] = useState("");
  const [downloadUrl, setDownloadUrl] = useState("");
  const [copyNotice, setCopyNotice] = useState("");

  useEffect(() => {
    onStatusChange(status);
  }, [status, onStatusChange]);

  useEffect(() => {
    return () => {
      onStatusChange("idle");
    };
  }, [onStatusChange]);

  const statusLabel = useMemo(() => {
    if (status === "uploading") return "Uploading...";
    if (status === "done") return "Upload complete";
    if (status === "failed") return "Upload failed";
    return "Ready";
  }, [status]);

  const handleFileChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setFile(event.target.files?.[0] ?? null);
    setStatus("idle");
    setError("");
    setDownloadUrl("");
    setCopyNotice("");
  };

  const formatError = (statusCode: number, bodyText: string) => {
    try {
      const data = JSON.parse(bodyText) as { error?: string };
      if (data?.error) {
        return `Upload failed (${statusCode} ${data.error.replace(/_/g, " ")})`;
      }
    } catch {}
    return `Upload failed (${statusCode})`;
  };

  const handleUpload = async () => {
    if (!file) {
      setStatus("failed");
      setError("Upload failed (no file selected)");
      return;
    }

    const nameParts = file.name.split(".");
    const extension = nameParts.length > 1 ? nameParts[nameParts.length - 1] : "";
    if (!extension) {
      setStatus("failed");
      setError("Upload failed (file extension required)");
      return;
    }

    setStatus("uploading");
    setError("");
    setDownloadUrl("");
    setCopyNotice("");

    try {
      const form = new FormData();
      form.append("file", file, `upload.${extension}`);
      const response = await fetch("/upload", { method: "POST", body: form });
      const bodyText = await response.text();

      if (!response.ok) {
        throw new Error(formatError(response.status, bodyText));
      }

      const data = JSON.parse(bodyText) as { token?: string };
      if (!data?.token) {
        throw new Error("Upload failed (invalid response)");
      }

      const url = `${window.location.origin}/download/${data.token}`;
      setDownloadUrl(url);
      setStatus("done");
    } catch (err) {
      const message = err instanceof Error ? err.message : "Upload failed";
      setStatus("failed");
      setError(message);
    }
  };

  const handleCopy = async () => {
    if (!downloadUrl) return;
    try {
      await navigator.clipboard.writeText(downloadUrl);
      setCopyNotice("Copied to clipboard.");
    } catch {
      setCopyNotice("Copy failed (use Ctrl+C).");
    }
  };

  const handleOpen = () => {
    if (!downloadUrl) return;
    window.open(downloadUrl, "_blank", "noopener,noreferrer");
  };

  const handleCloseDialog = () => {
    setDownloadUrl("");
    setCopyNotice("");
    setError("");
    setStatus("idle");
  };

  return (
    <WindowShell
      title={windowTitle}
      toolbarLabel="Select a file:"
      toolbarValue="Upload"
      sidebarTitle="Upload"
      sidebarItems={[
        { label: "Landing", to: "/" },
        { label: "Upload", active: true },
        { label: "Info", to: "/info" },
      ]}
      footerLabel="Help"
      statusLabel={statusLabel}
      onTitleClick={onTitleClick}
      onTitlePointerDown={onTitlePointerDown}
      onNotRespondingExit={onNotRespondingExit}
      onMaximize={onMaximize}
      isMaximized={isMaximized}
      isNotResponding={isNotResponding}
      windowStyle={windowStyle}
      windowRef={windowRef}
    >
      <div className="content-stack">
        <div className="group-box">
          <div className="group-title">Upload</div>
          <p className="subtitle">
            Select one file, then upload to get a shareable download link.
          </p>
          <div className="field-row">
            <label htmlFor="file-input">File</label>
            <input
              id="file-input"
              type="file"
              onChange={handleFileChange}
              disabled={isNotResponding}
            />
          </div>
          <div className="button-row">
            <button
              className="btn primary"
              onClick={handleUpload}
              disabled={status === "uploading" || isNotResponding}
            >
              Upload
            </button>
            <Link to="/" className={`btn ${isNotResponding ? "btn-disabled" : ""}`}>
              Back
            </Link>
          </div>
          {error ? <div className="error-box">{error}</div> : null}
        </div>
      </div>
      {downloadUrl && status === "done" ? (
        <div className="dialog-backdrop">
          <div className="dialog-window" role="dialog" aria-label="Upload complete">
            <div className="dialog-title">Upload complete</div>
            <div className="dialog-body">
              <label htmlFor="download-link" className="dialog-label">
                Download link:
              </label>
              <input
                id="download-link"
                type="text"
                readOnly
                value={downloadUrl}
                className="dialog-input"
              />
              {copyNotice ? <div className="dialog-status">{copyNotice}</div> : null}
            </div>
            <div className="dialog-buttons">
              <button className="btn" onClick={handleCopy} disabled={isNotResponding}>
                Copy
              </button>
              <button className="btn" onClick={handleOpen} disabled={isNotResponding}>
                Open
              </button>
              <button className="btn" onClick={handleCloseDialog} disabled={isNotResponding}>
                Close
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </WindowShell>
  );
};

const InfoPage = ({
  windowTitle,
  isMaximized,
  isNotResponding,
  windowStyle,
  windowRef,
  onTitleClick,
  onTitlePointerDown,
  onNotRespondingExit,
  onMaximize,
}: PageProps) => {
  return (
    <WindowShell
      title={windowTitle}
      toolbarLabel="Select a directory:"
      toolbarValue="Info"
      sidebarTitle="Info"
      sidebarItems={[
        { label: "Landing", to: "/" },
        { label: "Upload", to: "/upload" },
        { label: "Info", active: true },
      ]}
      footerLabel="Help"
      statusLabel="Ready"
      onTitleClick={onTitleClick}
      onTitlePointerDown={onTitlePointerDown}
      onNotRespondingExit={onNotRespondingExit}
      onMaximize={onMaximize}
      isMaximized={isMaximized}
      isNotResponding={isNotResponding}
      windowStyle={windowStyle}
      windowRef={windowRef}
    >
      <div className="content-stack">
        <div className="group-box">
          <div className="group-title">Info</div>
          <p className="subtitle">
            Parcel is a thin client over the API. Uploads return a shareable link that
            is the only access mechanism.
          </p>
        </div>
        <div className="group-box">
          <div className="group-title">How to use</div>
          <ul>
            <li>Upload a single file.</li>
            <li>Copy the link you receive.</li>
            <li>Share the link with anyone who should access it.</li>
          </ul>
        </div>
        <div className="group-box alert">
          <div className="group-title">Limitations</div>
          <ul>
            <li>No accounts or identity.</li>
            <li>No file listing or history.</li>
            <li>Link possession is access.</li>
          </ul>
        </div>
      </div>
    </WindowShell>
  );
};

function App() {
  const titleClickCountRef = useRef(0);
  const [isNotResponding, setIsNotResponding] = useState(false);
  const [uploadStatus, setUploadStatus] = useState<UploadStatus>("idle");
  const windowRef = useRef<HTMLDivElement | null>(null);
  const [position, setPosition] = useState({ x: 80, y: 60 });
  const [size, setSize] = useState({ width: 860, height: 520 });
  const [isMaximized, setIsMaximized] = useState(true);
  const dragState = useRef({
    startX: 0,
    startY: 0,
    originX: 0,
    originY: 0,
    moved: false,
  });
  const restoreState = useRef({ x: 80, y: 60, width: 860, height: 520 });

  const isUploading = uploadStatus === "uploading";

  useEffect(() => {
    if (isMaximized) return;
    const handleResize = () => {
      const rect = windowRef.current?.getBoundingClientRect();
      const currentWidth = rect ? Math.round(rect.width) : size.width;
      const currentHeight = rect ? Math.round(rect.height) : size.height;
      setSize({ width: currentWidth, height: currentHeight });
      setPosition((prev) => {
        const maxX = Math.max(0, window.innerWidth - currentWidth - 24);
        const maxY = Math.max(0, window.innerHeight - currentHeight - 24);
        return {
          x: Math.min(prev.x, maxX),
          y: Math.min(prev.y, maxY),
        };
      });
    };
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, [isMaximized, size.height, size.width]);

  const handleNotRespondingExit = () => {
    if (!isNotResponding) return;
    setIsNotResponding(false);
    titleClickCountRef.current = 0;
  };

  const handleTitleClick = () => {
    if (dragState.current.moved) {
      dragState.current.moved = false;
      return;
    }
    if (isNotResponding) {
      handleNotRespondingExit();
      return;
    }
    if (isUploading) return;
    titleClickCountRef.current += 1;
    if (titleClickCountRef.current >= 5) {
      setIsNotResponding(true);
      titleClickCountRef.current = 0;
    }
  };

  const handleTitlePointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (isMaximized || isNotResponding || event.button !== 0) return;
    event.preventDefault();
    const rect = windowRef.current?.getBoundingClientRect();
    const currentWidth = rect ? Math.round(rect.width) : size.width;
    const currentHeight = rect ? Math.round(rect.height) : size.height;
    setSize({ width: currentWidth, height: currentHeight });
    const startX = event.clientX;
    const startY = event.clientY;
    dragState.current = {
      startX,
      startY,
      originX: position.x,
      originY: position.y,
      moved: false,
    };

    const handleMove = (moveEvent: PointerEvent) => {
      const deltaX = moveEvent.clientX - startX;
      const deltaY = moveEvent.clientY - startY;
      if (Math.abs(deltaX) > 2 || Math.abs(deltaY) > 2) {
        dragState.current.moved = true;
      }
      const maxX = Math.max(0, window.innerWidth - currentWidth - 24);
      const maxY = Math.max(0, window.innerHeight - currentHeight - 24);
      const nextX = Math.min(Math.max(dragState.current.originX + deltaX, 0), maxX);
      const nextY = Math.min(Math.max(dragState.current.originY + deltaY, 0), maxY);
      setPosition({ x: nextX, y: nextY });
    };

    const handleUp = () => {
      window.removeEventListener("pointermove", handleMove);
      window.removeEventListener("pointerup", handleUp);
    };

    window.addEventListener("pointermove", handleMove);
    window.addEventListener("pointerup", handleUp);
  };

  const handleMaximize = () => {
    if (isNotResponding) return;
    if (isMaximized) {
      const restore = restoreState.current;
      setPosition({ x: restore.x, y: restore.y });
      setSize({ width: restore.width, height: restore.height });
      setIsMaximized(false);
      return;
    }
    const rect = windowRef.current?.getBoundingClientRect();
    const currentWidth = rect ? Math.round(rect.width) : size.width;
    const currentHeight = rect ? Math.round(rect.height) : size.height;
    restoreState.current = {
      x: position.x,
      y: position.y,
      width: currentWidth,
      height: currentHeight,
    };
    setIsMaximized(true);
  };

  const windowStyle: React.CSSProperties = isMaximized
    ? { left: 0, top: 0, width: "100%", height: "100%" }
    : { left: position.x, top: position.y, width: size.width, height: size.height };

  const windowTitle = isNotResponding ? "Parcel (Not Responding)" : "Parcel";

  return (
    <div className="desktop">
      <Routes>
        <Route
          path="/"
          element={
            <LandingPage
              windowTitle={windowTitle}
              isMaximized={isMaximized}
              isNotResponding={isNotResponding}
              windowStyle={windowStyle}
              windowRef={windowRef}
              onTitleClick={handleTitleClick}
              onTitlePointerDown={handleTitlePointerDown}
              onNotRespondingExit={handleNotRespondingExit}
              onMaximize={handleMaximize}
            />
          }
        />
        <Route
          path="/upload"
          element={
            <UploadPage
              windowTitle={windowTitle}
              isMaximized={isMaximized}
              isNotResponding={isNotResponding}
              windowStyle={windowStyle}
              windowRef={windowRef}
              onTitleClick={handleTitleClick}
              onTitlePointerDown={handleTitlePointerDown}
              onNotRespondingExit={handleNotRespondingExit}
              onMaximize={handleMaximize}
              onStatusChange={setUploadStatus}
            />
          }
        />
        <Route
          path="/info"
          element={
            <InfoPage
              windowTitle={windowTitle}
              isMaximized={isMaximized}
              isNotResponding={isNotResponding}
              windowStyle={windowStyle}
              windowRef={windowRef}
              onTitleClick={handleTitleClick}
              onTitlePointerDown={handleTitlePointerDown}
              onNotRespondingExit={handleNotRespondingExit}
              onMaximize={handleMaximize}
            />
          }
        />
      </Routes>
    </div>
  );
}

export default App;
