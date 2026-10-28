package logic

import (
	"server/config"
)

// ApiError 带 HTTP 状态与业务码的业务异常, 由 v1 控制器统一转换为响应
type ApiError struct {
	Status int
	Code   int
	Msg    string
	Cause  error
}

func (e *ApiError) Error() string {
	if e.Cause != nil {
		return e.Msg + ": " + e.Cause.Error()
	}
	return e.Msg
}

func (e *ApiError) Unwrap() error {
	return e.Cause
}

func NewBadRequest(msg string) *ApiError {
	return &ApiError{Status: 400, Code: config.V1CodeBadRequest, Msg: msg}
}

func NewUnauthorized(code int, msg string) *ApiError {
	return &ApiError{Status: 401, Code: code, Msg: msg}
}

func NewNotFound(msg string) *ApiError {
	return &ApiError{Status: 404, Code: config.V1CodeNotFound, Msg: msg}
}

func NewConflict(msg string) *ApiError {
	return &ApiError{Status: 409, Code: config.V1CodeConflict, Msg: msg}
}

func NewTooManyRequests(msg string) *ApiError {
	return &ApiError{Status: 429, Code: config.V1CodeTooManyRequests, Msg: msg}
}

func NewInternal(cause error) *ApiError {
	return &ApiError{Status: 500, Code: config.V1CodeInternal, Msg: "服务内部错误", Cause: cause}
}
