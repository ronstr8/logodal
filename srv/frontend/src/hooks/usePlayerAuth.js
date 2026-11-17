import { useState, useRef, useEffect, useCallback } from 'react';

export default function usePlayerAuth(i18n) {
    const [isAuthenticated, setIsAuthenticated] = useState(false);
    const [isAuthChecking, setIsAuthChecking] = useState(true);
    const [nickname, setNickname] = useState("");
    const [playerId, setPlayerId] = useState(null);
    const playerIdRef = useRef(null);

    const checkAuth = useCallback(async () => {
        try {
            const resp = await fetch('/auth/me');
            if (resp.ok) {
                const data = await resp.json();
                setPlayerId(data.id);
                playerIdRef.current = data.id;
                setNickname(data.nickname);
                if (data.language) i18n.changeLanguage(data.language);
                setIsAuthenticated(true);
                return data.id;
            }
        } catch (err) {
            console.error('Auth check failed:', err);
        } finally {
            setIsAuthChecking(false);
        }
        return null;
    }, [i18n]);

    const handleLogout = useCallback(async () => {
        try {
            await fetch('/auth/logout', { method: 'POST' });
            setIsAuthenticated(false);
            setPlayerId(null);
            playerIdRef.current = null;
            setNickname("");
        } catch (err) {
            console.error('Logout failed:', err);
        }
    }, []);

    useEffect(() => {
        checkAuth();
    }, [checkAuth]);

    return {
        isAuthenticated,
        isAuthChecking,
        nickname,
        setNickname,
        playerId,
        playerIdRef,
        checkAuth,
        handleLogout
    };
}
