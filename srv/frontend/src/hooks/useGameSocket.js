import { useState, useEffect, useRef, useCallback } from 'react';

export default function useGameSocket({
    playerId,
    nickname,
    i18n,
    onChatMessage,
    onGameStart,
    onTimer,
    onPlay,
    onPlayerJoined,
    onPlayerQuit,
    onError,
    onGameEnd,
    onIdentity,
    onChatHistory
}) {
    const [ws, setWs] = useState(null);
    const [isConnecting, setIsConnecting] = useState(true);
    const [connectionError, setConnectionError] = useState(null);
    const playerIdRef = useRef(playerId);

    useEffect(() => {
        playerIdRef.current = playerId;
    }, [playerId]);

    const handlersRef = useRef({});
    useEffect(() => {
        handlersRef.current = {
            onChatMessage, onGameStart, onTimer, onPlay,
            onPlayerJoined, onPlayerQuit, onError, onGameEnd,
            onIdentity, onChatHistory
        };
    }, [
        onChatMessage, onGameStart, onTimer, onPlay,
        onPlayerJoined, onPlayerQuit, onError, onGameEnd,
        onIdentity, onChatHistory
    ]);

    const connect = useCallback(() => {
        if (!playerId) return;
        
        const wsHost = window.location.host;
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        let socket = null;
        let reconnectTimeout = null;

        const startConnection = () => {
            if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) return;

            socket = new WebSocket(`${protocol}//${wsHost}/ws`);

            socket.onopen = () => {
                setWs(socket);
                setIsConnecting(false);
                setConnectionError(null);

                const urlParams = new URLSearchParams(window.location.search);
                const inviteGid = urlParams.get('invite');
                socket.send(JSON.stringify({
                    type: 'join',
                    payload: inviteGid ? { gid: inviteGid } : {}
                }));

                if (inviteGid) {
                    const newUrl = window.location.pathname;
                    window.history.replaceState({}, document.title, newUrl);
                }
            };

            socket.onerror = (error) => {
                console.error('WebSocket error:', error);
                setConnectionError('Connection failed');
            };

            socket.onclose = () => {
                setWs(null);
                setIsConnecting(true);
                reconnectTimeout = setTimeout(startConnection, 2000);
            };

            socket.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);
                    const handlers = handlersRef.current;
                    switch (data.type) {
                        case 'chat': handlers.onChatMessage?.(data); break;
                        case 'chat_history': handlers.onChatHistory?.(data); break;
                        case 'identity': handlers.onIdentity?.(data); break;
                        case 'game_start': handlers.onGameStart?.(data); break;
                        case 'timer': handlers.onTimer?.(data); break;
                        case 'play': handlers.onPlay?.(data); break;
                        case 'player_joined': handlers.onPlayerJoined?.(data); break;
                        case 'player_quit': handlers.onPlayerQuit?.(data); break;
                        case 'error': handlers.onError?.(data); break;
                        case 'game_end': handlers.onGameEnd?.(data); break;
                        default: console.warn('[WS] Unknown message type:', data.type);
                    }
                } catch (err) {
                    console.error('[WS] Error parsing message:', err);
                }
            };
        };

        startConnection();

        const handleVisibilityChange = () => {
            if (document.visibilityState === 'visible') {
                startConnection();
            }
        };
        document.addEventListener('visibilitychange', handleVisibilityChange);

        return () => {
            document.removeEventListener('visibilitychange', handleVisibilityChange);
            if (socket) socket.close();
            if (reconnectTimeout) clearTimeout(reconnectTimeout);
        };
    }, [playerId]); // Only depend on playerId

    useEffect(() => {
        const cleanup = connect();
        return cleanup;
    }, [connect]);

    const sendMessage = useCallback((type, payload) => {
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type, payload }));
            return true;
        }
        return false;
    }, [ws]);

    return { ws, isConnecting, connectionError, sendMessage };
}
