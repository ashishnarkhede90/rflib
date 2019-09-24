/*
 * Copyright (c) 2019 Johannes Fischer <fischer.jh@gmail.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of mosquitto nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * @group Logger
 * @description Default rflib_Logger implementation, which is based on the configuration
 *              stored in the Logger Settings Custom Setting object. 
 */ 
@SuppressWarnings('PMD.ClassNamingConventions')
public without sharing class rflib_DefaultLogger implements rflib_Logger {

  private static final Integer MAX_MESSAGE_SIZE = 131072;
  private static final List<String> LOG_STATEMENTS = new List<String>(); 

  private final String context;
  private final rflib_DefaultLogger.DebugLogger debugLogger;
  private final rflib_DefaultLogger.EventPublisher eventPublisher;

  private Integer logCacheSize = 100;

  private rflib_LogLevel systemDebugLevel = rflib_LogLevel.INFO;
  private rflib_LogLevel reportingLogLevel = rflib_LogLevel.FATAL;

  /**
   * Create an rflib_Logger instance for the given context based on the configuration of the Logger Custom Settings
   * associated with this user.
   * 
   * @param  context The context identifier for this logger instance.
   * @return         A logger instance for the given context.
   */
  public static rflib_Logger createFromCustomSettings(String context) {
    rflib_Logger logger = rflib_DefaultLogger.create(context);

    rflib_Logger_Settings__c settings = rflib_Logger_Settings__c.getInstance();
    if (settings.Log_Size__c != null) {
      logger.setLogCacheSize(Integer.valueOf(settings.Log_Size__c));
    }

    if (String.isNotBlank(settings.System_Debug_Log_Level__c)) {
      logger.setSystemDebugLevel(rflib_LogLevel.fromString(settings.System_Debug_Log_Level__c));
    }

    if (String.isNotBlank(settings.Log_Event_Reporting_Level__c)) {
      logger.setReportingLogLevel(rflib_LogLevel.fromString(settings.Log_Event_Reporting_Level__c));
    }

    return logger;
  }

  /**
   * Create a default logger instance for the given context. Default values for the logger are:
   *    - cache size: 100
   *    - system debug level: INFO
   *    - reporting log level: FATAL
   *
   * @param  context The context for this logger.
   * @return         The new logger instance for the given context.
   */
  public static rflib_Logger create(String context) {
    return new rflib_DefaultLogger(context);
  }
  
  private rflib_DefaultLogger(String context) {
    this(
      new rflib_DefaultLogger.PlatformEventPublisher(), 
      new rflib_DefaultLogger.SystemDebugLogger(), 
      context
    );
  }

  @TestVisible
  private rflib_DefaultLogger(
        rflib_DefaultLogger.EventPublisher eventPublisher, 
        rflib_DefaultLogger.DebugLogger debugLogger, 
        String context) {
    this.eventPublisher = eventPublisher;
    this.debugLogger = debugLogger;
    this.context = context;
  }

  public void setLogCacheSize(Integer newSize) {
    logCacheSize = newSize;

    Integer numberOfCollectedMessages = LOG_STATEMENTS.size();
    if (numberOfCollectedMessages > newSize) {
      for (Integer i = 0; i < (numberOfCollectedMessages - newSize); i++) {
        LOG_STATEMENTS.remove(0);
      }
    }
  } 

  public void setReportingLogLevel(rflib_LogLevel newLevev) {
    reportingLogLevel = newLevev;
  }

  public void setSystemDebugLevel(rflib_LogLevel newLevev) {
    systemDebugLevel = newLevev;
  }

  public void debug(String message) {
    debug(message, null);
  }
  public void debug(String message, Object[] args) {
    logMessage(rflib_LogLevel.DEBUG, message, args);
  }

  public void info(String message){
    info(message, null);
  }
  public void info(String message, Object[] args) {
    logMessage(rflib_LogLevel.INFO, message, args);
  }

  public void warn(String message){
    warn(message, null);
  }
  public void warn(String message, Object[] args) {
    logMessage(rflib_LogLevel.WARN, message, args);
  }

  public void error(String message){
    error(message, null);
  }
  public void error(String message, Object[] args) {
    logMessage(rflib_LogLevel.ERROR, message, args);
  }

  public void fatal(String message){
    fatal(message, null);
  }
  public void fatal(String message, Object[] args) {
    logMessage(rflib_LogLevel.FATAL, message, args);
  }

  public void printLogs() {
    debugLogger.debug(LoggingLevel.DEBUG, 'Log statements reported by ' + context + ':\n' + String.join(LOG_STATEMENTS, '\n'));
  }

  public void reportLogs() {
    String messagesAsStr = String.join(LOG_STATEMENTS, '\n');
    Integer messageSize = messagesAsStr.length();

    eventPublisher.publish(new rflib_Log_Event__e(
      Context__c = context,
      Log_Messages__c = messageSize < MAX_MESSAGE_SIZE
        ? messagesAsStr 
        : messagesAsStr.substring(messageSize - MAX_MESSAGE_SIZE, MAX_MESSAGE_SIZE)
    ));
  }

  private void logMessage(rflib_LogLevel logLevel, String message, Object[] args) {
    
    String messageToLog = DateTime.now().format() + '|' + logLevel + '|' + context;
    
    messageToLog = args == null 
      ? messageToLog + '|' + message
      : messageToLog + '|' + String.format(message, args);

    if (systemDebugLevel.encompasses(logLevel)) {
      debugLogger.debug(logLevel.getLoggingLevel(), messageToLog);
    }

    if (LOG_STATEMENTS.size() >= logCacheSize) {
      LOG_STATEMENTS.remove(0);
    }

    LOG_STATEMENTS.add(messageToLog);

    if (reportingLogLevel.encompasses(logLevel)) {
      reportLogs();
    }
  }

  public interface DebugLogger {
    void debug(LoggingLevel level, String message);
  }

  public class SystemDebugLogger implements DebugLogger {
    public void debug(LoggingLevel level, String message) {
      System.debug(level, message);
    }
  }

  public interface EventPublisher {
    void publish(SObject event);
  }

  public class PlatformEventPublisher implements EventPublisher {
    public void publish(Sobject event) {
      EventBus.publish(event);
    }
  }
}