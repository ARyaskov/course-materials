package io.meterway.domain;

public class UnknownMeterException extends MeterwayException {

    private final String meterCode;

    public UnknownMeterException(String meterCode) {
        super("Метрика не зарегистрирована: " + meterCode);
        this.meterCode = meterCode;
    }

    public String meterCode() {
        return meterCode;
    }

    @Override
    public String problemType() {
        return "unknown-meter";
    }
}
