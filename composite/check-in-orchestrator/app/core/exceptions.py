from http import HTTPStatus


class AppException(Exception):
    def __init__(self, message: str, status_code: int = HTTPStatus.INTERNAL_SERVER_ERROR) -> None:
        super().__init__(message)
        self.message = message
        self.status_code = status_code


class ExternalServiceError(AppException):
    def __init__(self, message: str, status_code: int = HTTPStatus.BAD_GATEWAY) -> None:
        super().__init__(message=message, status_code=status_code)


class ValidationError(AppException):
    def __init__(self, message: str, status_code: int = HTTPStatus.BAD_REQUEST) -> None:
        super().__init__(message=message, status_code=status_code)
