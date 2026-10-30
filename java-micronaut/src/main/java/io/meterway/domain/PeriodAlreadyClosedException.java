package io.meterway.domain;

public class PeriodAlreadyClosedException extends MeterwayException {

    private final String period;

    public PeriodAlreadyClosedException(String period) {
        super("Расчётный период уже закрыт: " + period);
        this.period = period;
    }

    public String period() {
        return period;
    }

    @Override
    public String problemType() {
        return "period-already-closed";
    }
}
