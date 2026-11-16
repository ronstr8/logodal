import React from 'react';
import { useTranslation } from 'react-i18next';
import Tile from './Tile';
import Timer from './Timer';
import { lengthBonus } from '../scoring';

const GameArea = ({ 
    state, 
    interaction, 
    isAuthenticated 
}) => {
    const { t } = useTranslation();
    const {
        rack, letterValue, timeLeft, totalTime, isLocked, guess, feedback, mutantLetter,
        lengthBonusStart, lengthBonusBase
    } = state;

    return (
        <main className="game-area">
            <div className="main-game-layout">
                <div className="center-panel">
                    <div className="rack-section">
                        <div className="section-label">{t('app.rack_label')}</div>
                        <div className="rack-content">
                            <div className="rack-container clickable">
                                {Array.from({ length: rack.length }).map((_, position) => {
                                    const tile = rack.find(t => t.position === position);
                                    if (!tile) return <div key={position} className="rack-slot empty" />;
                                    return (
                                        <div key={tile.id} className={`rack-slot ${tile.isUsed ? 'used' : ''}`} onClick={() => !tile.isUsed && interaction.moveTileToGuess(tile)}>
                                            <Tile letter={tile.letter} value={letterValue?.[tile.letter]} disabled={tile.isUsed} isMutant={!!mutantLetter && tile.letter === mutantLetter} />
                                        </div>
                                    );
                                })}
                                {rack.length === 0 && <div className="empty-rack-msg">{t('app.empty_rack')}</div>}
                            </div>
                            <Timer seconds={timeLeft} total={totalTime} />
                        </div>
                        <div className="rack-actions">
                            <button className="jumble-btn" onClick={interaction.jumbleRack} disabled={isLocked || timeLeft === 0 || rack.length === 0}>{t('app.jumble')}</button>
                            <button className="clear-btn" onClick={interaction.clearGuess} disabled={isLocked || timeLeft === 0 || guess.every(g => g === null)}>{t('app.clear')}</button>
                        </div>
                    </div>

                    <div className="input-section">
                        <div className="section-label">{t('app.word_label')}</div>
                        <div className="word-board">
                            {guess.map((slot, i) => {
                                const isFirstEmpty = guess.findIndex(g => g === null) === i;
                                // Filling slot i makes an (i+1)-letter word; the badge shows that word's length bonus.
                                const bonusPoints = lengthBonus(i + 1, lengthBonusStart, lengthBonusBase);
                                const isBonusSlot = bonusPoints > 0;
                                return (
                                    <div key={i} className={`board-slot ${slot ? 'filled' : 'empty'} ${isFirstEmpty && !isLocked && timeLeft > 0 ? 'focused' : ''} ${isBonusSlot ? 'bonus' : ''}`} onClick={() => slot && interaction.returnToRack(i)}>
                                        {isBonusSlot && slot && <div className="slot-badge">+{bonusPoints}</div>}
                                        {slot ? <Tile letter={slot.char} value={letterValue?.[slot.originalLetter || slot.char.toUpperCase()]} isMutant={!!mutantLetter && (slot.originalLetter || slot.char.toUpperCase()) === mutantLetter} /> : <div className="slot-placeholder"></div>}
                                    </div>
                                );
                            })}
                        </div>
                        <div className="submit-container">
                            <button className="submit-btn" onClick={interaction.submitWord} disabled={isLocked || timeLeft === 0 || guess.every(g => g === null)}>{t('app.submit')}</button>
                            {feedback.text && <div className={`feedback-label ${feedback.type} visible`}>{feedback.text}</div>}
                        </div>
                    </div>
                </div>
            </div>
        </main>
    );
};

export default GameArea;
